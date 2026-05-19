require 'net/http'
require 'uri'
require 'cgi'

# Base client for ASP.NET sweepstakes panels (Cluster 1).
# Implements the 6-step recipe verified end-to-end via PowerShell:
#   1. GET search page → scrape __VIEWSTATE + __VIEWSTATEGENERATOR
#   2. POST search with EVENTTARGET=ctl16 + txtSearch → scrape updateSelect('uid,gid')
#   3. GET Operating.ashx?action=resetpwauth&UserName=<agent> (auth gate, must return valid:true)
#   4. POST AccountsList.aspx with tourl=N + getpassuid + getpassgid → returns "PATH|x"
#   5. GET <PATH> → scrape fresh __VIEWSTATE + __VIEWSTATEGENERATOR + __EVENTVALIDATION
#   6. POST <PATH> with EVENTTARGET=Button1 + tokens + action-specific fields
#
# tourl values: 0=Recharge, 1=Redeem, 2=Reset Password, 6=Create Player
# Create uses EVENTTARGET=ctl07 + URL CreateAccount.aspx (no param).
#
# Subclasses must define constant BASE_URL.
#
# Credentials shape in agent_game.credentials JSONB:
#   { "agent_username" => "hamro555", "asp_session_id" => "e0acki32o1hdizslxtcx5z0w" }
#
# user_id format passed through ActionExecutor: "uid:gid" (we split on ':' inside).
module Games
  module AspNetPanel
    class BaseClient
      # Subclasses MUST override
      BASE_URL = nil

      OPEN_TIMEOUT = 10
      READ_TIMEOUT = 25

      USER_AGENT = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/145.0.0.0 Safari/537.36'.freeze

      attr_reader :agent_game

      def initialize(agent_game)
        @agent_game = agent_game
        creds = agent_game.credentials || {}
        @agent_username = creds['agent_username'].to_s.strip
        @session_id = creds['asp_session_id'].to_s.strip
        raise ArgumentError, 'Missing agent_username in credentials' if @agent_username.blank?
        raise ArgumentError, 'Missing asp_session_id in credentials' if @session_id.blank?
        raise ArgumentError, "BASE_URL not set on #{self.class.name}" if self.class::BASE_URL.blank?
      end

      # ============ Universal interface ============

      def test_connection
        resp = http_request(:get, search_url, headers: nav_headers(referer: search_url))
        if resp.body.to_s.include?('default.aspx') && resp.body.to_s.length < 5000
          { ok: false, code: -1, message: 'Session expired — re-capture asp_session_id' }
        else
          { ok: true, balance: extract_agent_balance(resp.body), message: 'Connected' }
        end
      rescue Games::ClientError => e
        { ok: false, code: e.code, message: e.message }
      rescue StandardError => e
        { ok: false, code: -1, message: "Connection failed: #{e.class}: #{e.message}" }
      end

      def agent_balance
        resp = http_request(:get, search_url, headers: nav_headers(referer: search_url))
        bal = extract_agent_balance(resp.body)
        { 'data' => { 'agent_balance' => bal }, 'code' => 0, 'msg' => 'Success' }
      end

      def get_user_id(account_name:)
        # Run steps 1+2 to resolve username → uid+gid. Return as "uid:gid".
        vs1, vsg1 = scrape_viewstate(fetch_search_page.body)
        body = "__EVENTTARGET=ctl16&__EVENTARGUMENT=&__VIEWSTATE=#{CGI.escape(vs1)}&__VIEWSTATEGENERATOR=#{CGI.escape(vsg1)}&__SCROLLPOSITIONX=0&__SCROLLPOSITIONY=0&txtSearch=#{CGI.escape(account_name.to_s)}&ShowHideAccount=1"
        resp = http_request(:post, search_url, body: body,
          headers: nav_headers(referer: search_url).merge(
            'Origin' => self.class::BASE_URL,
            'Content-Type' => 'application/x-www-form-urlencoded'))
        m = resp.body.to_s.match(/updateSelect\(\s*'(\d+),(\d+)'\s*\)/)
        if m
          { 'data' => { 'user_id' => "#{m[1]}:#{m[2]}" }, 'code' => 0, 'msg' => 'Found' }
        else
          { 'data' => nil, 'code' => -1, 'msg' => "Player '#{account_name}' not found" }
        end
      end

      def user_balance(user_id:)
        # ASP.NET panel only returns balance via search page table — search again.
        # user_id format = "uid:gid"; we extract account_name from the search match too if needed,
        # but ActionExecutor only ever calls this after get_user_id has produced the user_id.
        # So we look up the row in the listing for the target uid+gid pair.
        uid, gid = split_uid_gid(user_id)
        # Search by gid (works on all 4 panels; gid is the visible "Account ID" column key)
        resp = http_request(:get, search_url, headers: nav_headers(referer: search_url))
        # Extract balance for matching gid row from the table
        balance = extract_player_balance_from_listing(resp.body, gid)
        if balance.nil?
          raise Games::ClientError.new("Could not extract player balance for gid=#{gid}", code: -1)
        end
        { 'data' => { 'user_balance' => balance }, 'code' => 0, 'msg' => 'Success' }
      end

      def add_user(account:, password:)
        add_player(account: account, login_pwd: password)
      end

      def add_player(account:, login_pwd:)
        run_create_dance(account, login_pwd)
      end

      def recharge(user_id:, amount:, order_id:)
        run_amount_action(user_id: user_id, tourl: 0, amount: amount, order_id: order_id, action_label: 'recharge')
      end

      def withdraw(user_id:, amount:, order_id:)
        run_amount_action(user_id: user_id, tourl: 1, amount: amount, order_id: order_id, action_label: 'withdraw')
      end

      def reset_player_password(user_id:, login_pwd:)
        run_reset_password_dance(user_id: user_id, new_password: login_pwd)
      end

      def force_player_offline(user_id:)
        # Not exposed by ASP.NET panel; surface as soft no-op
        { 'data' => nil, 'code' => -2, 'msg' => 'force_player_offline not supported on this panel' }
      end

      # ============ Private ============
      private

      def split_uid_gid(user_id)
        parts = user_id.to_s.split(':', 2)
        raise Games::ClientError.new("Invalid user_id format (expected uid:gid): #{user_id}", code: -1) if parts.length != 2
        [parts[0], parts[1]]
      end

      def search_url
        "#{self.class::BASE_URL}/Module/AccountManager/AccountsList.aspx"
      end

      def auth_url
        "#{self.class::BASE_URL}/Tools/Operating.ashx?action=resetpwauth&UserName=#{CGI.escape(@agent_username)}"
      end

      def nav_headers(referer:)
        {
          'User-Agent' => USER_AGENT,
          'Accept' => 'text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,image/apng,*/*;q=0.8',
          'Accept-Language' => 'en-US,en;q=0.9',
          'Sec-Ch-Ua' => '"Google Chrome";v="145", "Not.A/Brand";v="8", "Chromium";v="145"',
          'Sec-Ch-Ua-Mobile' => '?0',
          'Sec-Ch-Ua-Platform' => '"Windows"',
          'Sec-Fetch-Dest' => 'iframe',
          'Sec-Fetch-Mode' => 'navigate',
          'Sec-Fetch-Site' => 'same-origin',
          'Upgrade-Insecure-Requests' => '1',
          'Referer' => referer,
          'Cookie' => "ASP.NET_SessionId=#{@session_id}"
        }
      end

      def xhr_headers(referer:)
        {
          'User-Agent' => USER_AGENT,
          'Accept' => 'application/json, text/javascript, */*; q=0.01',
          'Accept-Language' => 'en-US,en;q=0.9',
          'X-Requested-With' => 'XMLHttpRequest',
          'Sec-Ch-Ua' => '"Google Chrome";v="145", "Not.A/Brand";v="8", "Chromium";v="145"',
          'Sec-Ch-Ua-Mobile' => '?0',
          'Sec-Ch-Ua-Platform' => '"Windows"',
          'Sec-Fetch-Dest' => 'empty',
          'Sec-Fetch-Mode' => 'cors',
          'Sec-Fetch-Site' => 'same-origin',
          'Referer' => referer,
          'Cookie' => "ASP.NET_SessionId=#{@session_id}"
        }
      end

      def fetch_search_page
        http_request(:get, search_url, headers: nav_headers(referer: search_url))
      end

      def scrape_viewstate(body)
        vs = body.to_s.match(/id="__VIEWSTATE" value="([^"]+)"/)&.[](1)
        vsg = body.to_s.match(/id="__VIEWSTATEGENERATOR" value="([^"]+)"/)&.[](1)
        if vs.blank? || vsg.blank?
          raise Games::ClientError.new('Could not scrape __VIEWSTATE/__VIEWSTATEGENERATOR — session likely dead', code: -1)
        end
        [vs, vsg]
      end

      def scrape_event_validation(body)
        body.to_s.match(/id="__EVENTVALIDATION" value="([^"]+)"/)&.[](1).to_s
      end

      def extract_agent_balance(body)
        m = body.to_s.match(/updateBalance\("Balance:([\d.]+)"\)/)
        return nil unless m
        m[1].to_f
      end

      def extract_player_balance_from_listing(body, gid)
        # Each player row has gid in first <td>; balance is the 4th-ish column. Scrape conservatively.
        # Row pattern: updateSelect('uid,gid'); then later "<td style=\"color: red\">N.NN</td>"
        # We match the SINGLE row that contains updateSelect with this gid.
        row_re = /updateSelect\('(\d+),#{Regexp.escape(gid.to_s)}'\).*?<td[^>]*>\s*([\d.]+)\s*<\/td>\s*<td[^>]*>\s*[\d.]+\s*<\/td>\s*<td[^>]*>\s*[\d.]+\s*<\/td>\s*<td[^>]*color:\s*red[^>]*>\s*([\d.]+)\s*<\/td>/mi
        m = body.to_s.match(row_re)
        return nil unless m
        m[3].to_f
      end

      def hit_auth_gate
        # Step 3 in recipe — must return valid:true; we don't parse, just fire
        http_request(:get, auth_url, headers: xhr_headers(referer: search_url))
      end

      def fetch_action_url(tourl:, uid:, gid:)
        # Step 4: POST AccountsList with tourl/getpassuid/getpassgid → returns "PATH|x"
        body = "tourl=#{tourl}&getpassuid=#{CGI.escape(uid.to_s)}&getpassgid=#{CGI.escape(gid.to_s)}"
        resp = http_request(:post, search_url, body: body,
          headers: xhr_headers(referer: search_url).merge(
            'Origin' => self.class::BASE_URL,
            'Content-Type' => 'application/x-www-form-urlencoded'))
        path = resp.body.to_s.split('|', 2).first.to_s.strip
        if path.blank?
          raise Games::ClientError.new("Server returned blank action URL for tourl=#{tourl}", code: -1, payload: { raw: resp.body[0..300] })
        end
        "#{self.class::BASE_URL}/#{path}"
      end

      def fetch_create_url
        # tourl=6 with empty uid/gid
        body = 'tourl=6&getpassuid=&getpassgid='
        resp = http_request(:post, search_url, body: body,
          headers: xhr_headers(referer: search_url).merge(
            'Origin' => self.class::BASE_URL,
            'Content-Type' => 'application/x-www-form-urlencoded'))
        path = resp.body.to_s.split('|', 2).first.to_s.strip
        if path.blank?
          raise Games::ClientError.new('Server returned blank create URL (tourl=6)', code: -1, payload: { raw: resp.body[0..300] })
        end
        "#{self.class::BASE_URL}/#{path}"
      end

      def run_amount_action(user_id:, tourl:, amount:, order_id:, action_label:)
        uid, gid = split_uid_gid(user_id)
        sleep_jitter(0.7)
        hit_auth_gate
        sleep_jitter(0.5)
        action_url = fetch_action_url(tourl: tourl, uid: uid, gid: gid)
        sleep_jitter(1.0)
        page = http_request(:get, action_url, headers: nav_headers(referer: search_url))
        vs, vsg = scrape_viewstate(page.body)
        ev = scrape_event_validation(page.body)
        sleep_jitter(1.2)
        amt_int = sanitize_whole_amount(amount, action_label)
        body = "__EVENTTARGET=Button1&__EVENTARGUMENT=&__VIEWSTATE=#{CGI.escape(vs)}&__VIEWSTATEGENERATOR=#{CGI.escape(vsg)}&__EVENTVALIDATION=#{CGI.escape(ev)}&txtAddGold=#{amt_int}&txtReason=#{CGI.escape("order:#{order_id}")}"
        resp = http_request(:post, action_url, body: body,
          headers: nav_headers(referer: action_url).merge(
            'Origin' => self.class::BASE_URL,
            'Content-Type' => 'application/x-www-form-urlencoded'))
        if resp.body.to_s.include?('Confirmed successful')
          { 'data' => { 'order_id' => order_id, 'amount' => amt_int }, 'code' => 0, 'msg' => "#{action_label} successful" }
        else
          err = resp.body.to_s.match(/showAlter\("([^"]+)"\)/)&.[](1) || 'Unknown server response'
          raise Games::ClientError.new("#{action_label} failed: #{err}", code: -1, payload: { snippet: resp.body[0..500] })
        end
      end

      def run_reset_password_dance(user_id:, new_password:)
        uid, gid = split_uid_gid(user_id)
        sleep_jitter(0.7)
        hit_auth_gate
        sleep_jitter(0.5)
        action_url = fetch_action_url(tourl: 2, uid: uid, gid: gid)
        sleep_jitter(1.0)
        page = http_request(:get, action_url, headers: nav_headers(referer: search_url))
        vs, vsg = scrape_viewstate(page.body)
        ev = scrape_event_validation(page.body)
        sleep_jitter(1.2)
        body = "__EVENTTARGET=Button1&__EVENTARGUMENT=&__VIEWSTATE=#{CGI.escape(vs)}&__VIEWSTATEGENERATOR=#{CGI.escape(vsg)}&__EVENTVALIDATION=#{CGI.escape(ev)}&textGameID=#{gid}&textAccounts=&txtConfirmPass=#{CGI.escape(new_password.to_s)}&txtSureConfirmPass=#{CGI.escape(new_password.to_s)}"
        resp = http_request(:post, action_url, body: body,
          headers: nav_headers(referer: action_url).merge(
            'Origin' => self.class::BASE_URL,
            'Content-Type' => 'application/x-www-form-urlencoded'))
        if resp.body.to_s.include?('Confirmed successful')
          { 'data' => { 'reset' => true }, 'code' => 0, 'msg' => 'Password reset successful' }
        else
          err = resp.body.to_s.match(/showAlter\("([^"]+)"\)/)&.[](1) || 'Unknown server response'
          raise Games::ClientError.new("Reset password failed: #{err}", code: -1, payload: { snippet: resp.body[0..500] })
        end
      end

      def run_create_dance(account, password)
        # Panel-enforced: account = max 13 chars [A-Za-z0-9_]
        safe_account = sanitize_panel_name(account)
        sleep_jitter(0.7)
        hit_auth_gate
        sleep_jitter(0.5)
        create_url = fetch_create_url
        sleep_jitter(1.0)
        page = http_request(:get, create_url, headers: nav_headers(referer: search_url))
        vs, vsg = scrape_viewstate(page.body)
        ev = scrape_event_validation(page.body)
        sleep_jitter(1.5)
        body = "__EVENTTARGET=ctl07&__EVENTARGUMENT=&__VIEWSTATE=#{CGI.escape(vs)}&__VIEWSTATEGENERATOR=#{CGI.escape(vsg)}&__EVENTVALIDATION=#{CGI.escape(ev)}&txtAccount=#{CGI.escape(safe_account)}&txtNickName=#{CGI.escape(safe_account)}&txtLogonPass=#{CGI.escape(password.to_s)}&txtLogonPass2=#{CGI.escape(password.to_s)}"
        resp = http_request(:post, create_url, body: body,
          headers: nav_headers(referer: create_url).merge(
            'Origin' => self.class::BASE_URL,
            'Content-Type' => 'application/x-www-form-urlencoded'))

        # Search-verify (Bug 12 lesson — popup text is not authoritative)
        sleep_jitter(1.5)
        lookup = get_user_id(account_name: safe_account)
        if lookup['data'].present?
          { 'data' => { 'user_id' => lookup['data']['user_id'], 'account' => safe_account }, 'code' => 0, 'msg' => 'Player created' }
        else
          err = resp.body.to_s.match(/showAlter\("([^"]+)"\)/)&.[](1) || 'Create reported success but player not found in search'
          raise Games::ClientError.new("Create failed: #{err}", code: -1, payload: { account: safe_account, snippet: resp.body[0..500] })
        end
      end

      def sanitize_panel_name(name)
        # Panel limit: 13 chars, [A-Za-z0-9_] only
        s = name.to_s.gsub(/[^A-Za-z0-9_]/, '')
        s[0, 13]
      end

      def sanitize_whole_amount(amount, action_label)
        f = amount.to_f
        i = f.to_i
        if f != i.to_f
          raise Games::ClientError.new("#{action_label} requires whole-dollar amount (got #{amount})", code: -1)
        end
        i
      end

      def sleep_jitter(base_seconds)
        sleep(base_seconds + rand * 0.4)
      rescue StandardError
        nil
      end

      def http_request(method, url_str, body: nil, headers: {})
        uri = URI(url_str)
        Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == 'https',
                        open_timeout: OPEN_TIMEOUT, read_timeout: READ_TIMEOUT) do |http|
          req = case method
                when :get
                  Net::HTTP::Get.new(uri.request_uri)
                when :post
                  r = Net::HTTP::Post.new(uri.request_uri)
                  r.body = body
                  r
                else
                  raise ArgumentError, "Unsupported HTTP method: #{method}"
                end
          headers.each { |k, v| req[k] = v }
          response = http.request(req)
          unless response.is_a?(Net::HTTPSuccess) || response.is_a?(Net::HTTPRedirection)
            raise Games::ClientError.new("HTTP #{response.code} on #{method.upcase} #{uri.path}", code: response.code.to_i, payload: { snippet: response.body.to_s[0..300] })
          end
          response
        end
      rescue Games::ClientError
        raise
      rescue Net::OpenTimeout, Net::ReadTimeout => e
        raise Games::ClientError.new("Timeout: #{e.message}", code: -1)
      rescue StandardError => e
        raise Games::ClientError.new("Network error: #{e.class}: #{e.message}", code: -1)
      end
    end
  end
end
