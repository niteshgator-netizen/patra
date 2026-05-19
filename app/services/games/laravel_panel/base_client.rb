require 'net/http'
require 'uri'
require 'cgi'
require 'json'

# Base client for Laravel/layui sweepstakes panels (Cluster 2).
# Clean JSON REST — much simpler than ASP.NET.
#
# Endpoints (POST, urlencoded body):
#   /api/player/playerInsert  → create player
#   /api/player/agentRecharge → recharge (opera_type=0)
#   /api/player/agentWithdraw → redeem (opera_type=1)
#   /api/player/reset         → reset password
#   /api/agent/getMoney       → POST, returns agent balance
# GET:
#   /api/player/userList?page=1&limit=20&Id=&account=X&nickname= → search
#
# Auth: Authorization: Bearer <JWT> + Cookie: <panel>_session=...; server_name_session=...
#
# Credentials shape in agent_game.credentials JSONB:
#   { "bearer" => "eyJ0...", "session_cookie" => "eyJpdiI6...", "server_name_session" => "abc123..." }
#
# IMPORTANT panel quirks (verified via PowerShell):
#   - userList returns JSON with BOTH "Id" and "id" duplicate keys — use regex scrape, not JSON.parse
#   - Create password: alphanumeric only, 6-12 chars (no underscores, no specials)
#   - Reset password: MUST have uppercase + lowercase + special, 6-12 chars
#   - Username: letters + numbers only, 5-20 chars, NO underscores
module Games
  module LaravelPanel
    class BaseClient
      # Subclasses MUST override
      BASE_URL = nil
      PANEL_KEY = nil  # e.g. 'mafia' → cookie name "mafia_session"

      OPEN_TIMEOUT = 10
      READ_TIMEOUT = 25

      USER_AGENT = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/145.0.0.0 Safari/537.36'.freeze

      attr_reader :agent_game

      def initialize(agent_game)
        @agent_game = agent_game
        creds = agent_game.credentials || {}
        @bearer = creds['bearer'].to_s.strip
        @session_cookie = creds['session_cookie'].to_s.strip
        @server_name_session = creds['server_name_session'].to_s.strip
        raise ArgumentError, 'Missing bearer in credentials' if @bearer.blank?
        raise ArgumentError, 'Missing session_cookie in credentials' if @session_cookie.blank?
        raise ArgumentError, "BASE_URL not set on #{self.class.name}" if self.class::BASE_URL.blank?
        raise ArgumentError, "PANEL_KEY not set on #{self.class.name}" if self.class::PANEL_KEY.blank?
      end

      # ============ Universal interface ============

      def test_connection
        bal_hash = agent_balance
        { ok: true, balance: bal_hash.dig('data', 'agent_balance'), message: 'Connected' }
      rescue Games::ClientError => e
        { ok: false, code: e.code, message: e.message }
      rescue StandardError => e
        { ok: false, code: -1, message: "Connection failed: #{e.class}: #{e.message}" }
      end

      def agent_balance
        resp = http_request(:post, "#{self.class::BASE_URL}/api/agent/getMoney",
                            body: '', headers: xhr_headers(referer: "#{self.class::BASE_URL}/admin/console"))
        json = JSON.parse(resp.body)
        if json['status_code'].to_i == 200
          { 'data' => { 'agent_balance' => json['data'] }, 'code' => 0, 'msg' => 'Success' }
        else
          raise Games::ClientError.new("agent_balance failed: #{json['message']}", code: json['status_code'].to_i)
        end
      end

      def get_user_id(account_name:)
        row = search_player(account_name)
        if row
          { 'data' => { 'user_id' => row['id'].to_s }, 'code' => 0, 'msg' => 'Found' }
        else
          { 'data' => nil, 'code' => -1, 'msg' => "Player '#{account_name}' not found" }
        end
      end

      def user_balance(user_id:)
        row = search_player_by_id(user_id)
        if row
          { 'data' => { 'user_balance' => row['score'].to_f }, 'code' => 0, 'msg' => 'Success' }
        else
          raise Games::ClientError.new("Player id=#{user_id} not found", code: -1)
        end
      end

      def add_user(account:, password:)
        add_player(account: account, login_pwd: password)
      end

      def add_player(account:, login_pwd:)
        body = "username=#{CGI.escape(account.to_s)}&nickname=#{CGI.escape(account.to_s)}&money=0&password=#{CGI.escape(login_pwd.to_s)}&password_confirmation=#{CGI.escape(login_pwd.to_s)}"
        resp = http_request(:post, "#{self.class::BASE_URL}/api/player/playerInsert",
                            body: body, headers: xhr_headers(
                              referer: "#{self.class::BASE_URL}/admin/player/insert",
                              extra: { 'Content-Type' => 'application/x-www-form-urlencoded; charset=UTF-8',
                                       'Origin' => self.class::BASE_URL }))
        json = JSON.parse(resp.body)
        if json['message'].to_s.match?(/successful/i)
          # Search-verify so we return the new id
          sleep_jitter(1.0)
          lookup = get_user_id(account_name: account)
          raise Games::ClientError.new('Create reported success but player not found', code: -1) if lookup['data'].nil?
          { 'data' => json['data'].is_a?(Hash) ? json['data'].merge('user_id' => lookup['data']['user_id']) : { 'user_id' => lookup['data']['user_id'] },
            'code' => 0, 'msg' => json['message'] }
        else
          raise Games::ClientError.new("Create failed: #{json['message']}", code: -1, payload: json)
        end
      end

      def recharge(user_id:, amount:, order_id:)
        agent_bal = agent_balance.dig('data', 'agent_balance')
        body = "id=#{CGI.escape(user_id.to_s)}&available_balance=#{CGI.escape(agent_bal.to_s)}&opera_type=0&bonus=0&balance=#{CGI.escape(amount.to_s)}&remark=#{CGI.escape("order:#{order_id}")}"
        post_action('agentRecharge', body, action_label: 'recharge', order_id: order_id)
      end

      def withdraw(user_id:, amount:, order_id:)
        customer_balance = user_balance(user_id: user_id).dig('data', 'user_balance')
        body = "id=#{CGI.escape(user_id.to_s)}&customer_balance=#{CGI.escape(customer_balance.to_s)}&opera_type=1&balance=#{CGI.escape(amount.to_s)}&remark=#{CGI.escape("order:#{order_id}")}"
        post_action('agentWithdraw', body, action_label: 'withdraw', order_id: order_id)
      end

      def reset_player_password(user_id:, login_pwd:)
        body = "id=#{CGI.escape(user_id.to_s)}&password=#{CGI.escape(login_pwd.to_s)}&password_confirmation=#{CGI.escape(login_pwd.to_s)}"
        resp = http_request(:post, "#{self.class::BASE_URL}/api/player/reset",
                            body: body, headers: xhr_headers(
                              referer: "#{self.class::BASE_URL}/admin/player/resetpw",
                              extra: { 'Content-Type' => 'application/x-www-form-urlencoded; charset=UTF-8',
                                       'Origin' => self.class::BASE_URL }))
        json = JSON.parse(resp.body)
        if json['message'].to_s.match?(/successful/i)
          { 'data' => json['data'], 'code' => 0, 'msg' => json['message'] }
        else
          raise Games::ClientError.new("Reset password failed: #{json['message']}", code: -1, payload: json)
        end
      end

      def force_player_offline(user_id:)
        { 'data' => nil, 'code' => -2, 'msg' => 'force_player_offline not yet mapped on this panel' }
      end

      # ============ Private ============
      private

      def post_action(endpoint, body, action_label:, order_id:)
        resp = http_request(:post, "#{self.class::BASE_URL}/api/player/#{endpoint}",
                            body: body, headers: xhr_headers(
                              referer: "#{self.class::BASE_URL}/admin/player/#{endpoint == 'agentRecharge' ? 'recharge' : 'withdraw'}",
                              extra: { 'Content-Type' => 'application/x-www-form-urlencoded; charset=UTF-8',
                                       'Origin' => self.class::BASE_URL }))
        json = JSON.parse(resp.body)
        if json['message'].to_s.match?(/successful/i)
          { 'data' => (json['data'] || {}).merge('order_id' => order_id), 'code' => 0, 'msg' => json['message'] }
        else
          raise Games::ClientError.new("#{action_label} failed: #{json['message']}", code: -1, payload: json)
        end
      end

      def search_player(account_name)
        url = "#{self.class::BASE_URL}/api/player/userList?page=1&limit=20&Id=&account=#{CGI.escape(account_name.to_s)}&nickname="
        resp = http_request(:get, url, headers: xhr_headers(referer: "#{self.class::BASE_URL}/admin/player/index"))
        scrape_first_row(resp.body)
      end

      def search_player_by_id(id)
        url = "#{self.class::BASE_URL}/api/player/userList?page=1&limit=20&Id=#{CGI.escape(id.to_s)}&account=&nickname="
        resp = http_request(:get, url, headers: xhr_headers(referer: "#{self.class::BASE_URL}/admin/player/index"))
        scrape_first_row(resp.body)
      end

      def scrape_first_row(raw)
        # JSON has duplicate keys "Id" and "id" which crashes JSON.parse strict mode in some envs;
        # use regex to extract just what we need from the first record.
        id_m = raw.to_s.match(/"Id":(\d+)/)
        return nil unless id_m
        score_m = raw.to_s.match(/"score":"?([0-9.]+)"?/)
        account_m = raw.to_s.match(/"Account":"([^"]+)"/)
        {
          'id' => id_m[1],
          'score' => score_m ? score_m[1] : '0',
          'account' => account_m ? account_m[1] : nil
        }
      end

      def cookie_header
        parts = []
        parts << "server_name_session=#{@server_name_session}" if @server_name_session.present?
        parts << "#{self.class::PANEL_KEY}_session=#{@session_cookie}"
        parts.join('; ')
      end

      def xhr_headers(referer:, extra: {})
        base = {
          'User-Agent' => USER_AGENT,
          'Accept' => 'application/json, text/javascript, */*; q=0.01',
          'Accept-Language' => 'en-US,en;q=0.9',
          'X-Requested-With' => 'XMLHttpRequest',
          'Authorization' => "Bearer #{@bearer}",
          'Sec-Ch-Ua' => '"Not:A-Brand";v="99", "Google Chrome";v="145", "Chromium";v="145"',
          'Sec-Ch-Ua-Mobile' => '?0',
          'Sec-Ch-Ua-Platform' => '"Windows"',
          'Sec-Fetch-Dest' => 'empty',
          'Sec-Fetch-Mode' => 'cors',
          'Sec-Fetch-Site' => 'same-origin',
          'Pragma' => 'no-cache',
          'Cache-Control' => 'no-cache',
          'Referer' => referer,
          'Cookie' => cookie_header
        }
        base.merge(extra)
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
                  r.body = body.to_s
                  r
                else
                  raise ArgumentError, "Unsupported HTTP method: #{method}"
                end
          headers.each { |k, v| req[k] = v }
          response = http.request(req)
          if response.is_a?(Net::HTTPUnauthorized)
            raise Games::ClientError.new('Bearer JWT expired — re-capture from browser', code: 401)
          end
          unless response.is_a?(Net::HTTPSuccess) || response.is_a?(Net::HTTPRedirection)
            raise Games::ClientError.new("HTTP #{response.code} on #{method.upcase} #{uri.path}", code: response.code.to_i, payload: { snippet: response.body.to_s[0..300] })
          end
          response
        end
      rescue Games::ClientError
        raise
      rescue JSON::ParserError => e
        raise Games::ClientError.new("Invalid JSON response: #{e.message}", code: -1)
      rescue Net::OpenTimeout, Net::ReadTimeout => e
        raise Games::ClientError.new("Timeout: #{e.message}", code: -1)
      rescue StandardError => e
        raise Games::ClientError.new("Network error: #{e.class}: #{e.message}", code: -1)
      end
    end
  end
end
