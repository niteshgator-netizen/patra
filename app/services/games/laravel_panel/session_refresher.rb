require 'net/http'
require 'uri'
require 'cgi'
require 'json'

# Re-logs into a Cluster 2 Laravel/layui sweepstakes panel and captures
# a fresh bearer JWT + session cookies. Writes them to
# agent_game.credentials in the shape the LaravelPanel::BaseClient expects:
#   { 'bearer' => '...', 'session_cookie' => '...', 'server_name_session' => '...' }
#
# Flow (verified end-to-end from Railway on May 20 2026):
#   1. GET BASE_URL/admin/login
#      - server sets <PANEL_KEY>_session + (usually) server_name_session cookies
#      - HTML contains <meta name="csrf-token" content="...">
#   2. POST BASE_URL/api/login
#      Body: username=<u>&password=<p>&captcha=abcd
#      Headers: X-CSRF-TOKEN, X-Requested-With, Cookie (cookies from step 1),
#               Content-Type application/x-www-form-urlencoded, Origin, Referer
#      NOTE: the captcha field is decoration — okGVerify generates the value
#      client-side only, server doesn't validate it. ANY 4-char string works.
#   3. Response is JSON: {status_code:200, message:"Users login succeeded",
#      token:"eyJ0...", userName:"hamro555", roleName:"Store",
#      money:"155.00", expires_time:<unix>, is_modify:1,
#      console_url:"https://.../admin/console"}
#      Set-Cookie may rotate <PANEL_KEY>_session and/or server_name_session.
#   4. Persist new bearer + (any rotated cookies) to agent_game.credentials.
#
# Usage:
#   refresher = Games::LaravelPanel::SessionRefresher.new(agent_game)
#   result = refresher.refresh!
#   # result = { ok: true, bearer_len: 360, expires_time: 1779282739 }
#   #          or { ok: false, error: "..." }
module Games
  module LaravelPanel
    class SessionRefresher
      USER_AGENT = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 ' \
                   '(KHTML, like Gecko) Chrome/145.0.0.0 Safari/537.36'.freeze

      OPEN_TIMEOUT = 10
      READ_TIMEOUT = 25

      # slug => [BASE_URL, PANEL_KEY]
      # MUST match the BASE_URL + PANEL_KEY in each subclass under
      # app/services/games/<slug>/client.rb. PANEL_KEY is also the prefix
      # of the panel session cookie name (e.g. mafia_session).
      PANELS = {
        'mafia'         => ['https://agentserver.mafia77777.com',     'mafia'],
        'game_room'     => ['https://agentserver.gameroom777.com',    'gameroom'],
        'cash_machine'  => ['https://agentserver.cashmachine777.com', 'cashmachine'],
        'mr_all_in_one' => ['https://agentserver.mrallinone777.com',  'mrallinone']
      }.freeze

      class RefreshError < StandardError; end

      attr_reader :agent_game

      def initialize(agent_game)
        @agent_game = agent_game
        @slug = agent_game.game.slug.to_s
        entry = PANELS[@slug] or
          raise RefreshError, "No Cluster 2 BASE_URL configured for slug=#{@slug}"
        @base_url, @panel_key = entry
        @username = agent_game.credentials['agent_username'].to_s.strip
        @password = agent_game.credentials['agent_password'].to_s.strip
        raise RefreshError, 'Missing agent_username in credentials' if @username.empty?
        raise RefreshError, 'Missing agent_password in credentials' if @password.empty?
        @cookies = {}
      end

      # Main entry point.
      # Returns { ok: true, bearer_len:, expires_time: } on success
      # or { ok: false, error: "..." } on failure.
      def refresh!
        log("starting Cluster 2 refresh for #{@slug}")
        page_html = fetch_login_page
        csrf = extract_csrf_token(page_html)
        log("cookies captured: #{@cookies.keys.inspect}, csrf len=#{csrf.length}")

        login_response = post_login(csrf)
        body_str = login_response.body.to_s
        json = JSON.parse(body_str)

        unless json['status_code'].to_i == 200
          raise RefreshError, "Login failed: status_code=#{json['status_code']} message=#{json['message']}"
        end

        new_bearer = json['token'].to_s
        raise RefreshError, 'Login response had no token field' if new_bearer.empty?

        persist_new_credentials(new_bearer)
        log("✅ refresh ok — bearer_len=#{new_bearer.length}, expires_time=#{json['expires_time']}")

        { ok: true, bearer_len: new_bearer.length, expires_time: json['expires_time'] }
      rescue StandardError => e
        log("❌ refresh failed: #{e.class}: #{e.message}")
        { ok: false, error: "#{e.class}: #{e.message}" }
      end

      private

      def fetch_login_page
        uri = URI("#{@base_url}/admin/login")
        response = http_get(uri, headers: nav_headers)
        update_cookies_from_response(response)
        body = response.body.to_s
        unless body.include?('csrf-token')
          raise RefreshError, "Login page missing csrf-token meta (body length=#{body.length})"
        end
        body
      end

      def extract_csrf_token(body)
        m = body.match(/name="csrf-token"\s+content="([^"]+)"/)
        raise RefreshError, 'CSRF token not found in login HTML' unless m
        m[1]
      end

      def post_login(csrf)
        uri = URI("#{@base_url}/api/login")
        # captcha=abcd is deliberate — okGVerify is client-side only,
        # server ignores the field. Verified May 20 2026.
        body = "username=#{CGI.escape(@username)}" \
               "&password=#{CGI.escape(@password)}" \
               "&captcha=abcd"
        response = http_post(uri, body, headers: xhr_headers(csrf: csrf))
        update_cookies_from_response(response)
        response
      end

      def persist_new_credentials(new_bearer)
        creds = @agent_game.credentials.merge('bearer' => new_bearer)
        session_cookie_name = "#{@panel_key}_session"
        if (sess = @cookies[session_cookie_name])
          creds = creds.merge('session_cookie' => sess)
        end
        if (snss = @cookies['server_name_session'])
          creds = creds.merge('server_name_session' => snss)
        end
        @agent_game.credentials = creds
        @agent_game.save!
      end

      # ============ HTTP helpers ============

      def http_get(uri, headers:)
        Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == 'https',
                        open_timeout: OPEN_TIMEOUT, read_timeout: READ_TIMEOUT) do |http|
          req = Net::HTTP::Get.new(uri.request_uri)
          headers.each { |k, v| req[k] = v }
          http.request(req)
        end
      end

      def http_post(uri, body, headers:)
        Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == 'https',
                        open_timeout: OPEN_TIMEOUT, read_timeout: READ_TIMEOUT) do |http|
          req = Net::HTTP::Post.new(uri.request_uri)
          headers.each { |k, v| req[k] = v }
          req.body = body
          http.request(req)
        end
      end

      def nav_headers
        {
          'User-Agent' => USER_AGENT,
          'Accept' => 'text/html,application/xhtml+xml,application/xml;q=0.9',
          'Accept-Language' => 'en-US,en;q=0.9',
          'Cookie' => cookie_header
        }.reject { |_, v| v.to_s.empty? }
      end

      def xhr_headers(csrf:)
        {
          'User-Agent' => USER_AGENT,
          'Accept' => 'application/json',
          'Accept-Language' => 'en-US,en;q=0.9',
          'X-Requested-With' => 'XMLHttpRequest',
          'X-CSRF-TOKEN' => csrf,
          'Origin' => @base_url,
          'Referer' => "#{@base_url}/admin/login",
          'Content-Type' => 'application/x-www-form-urlencoded; charset=UTF-8',
          'Cookie' => cookie_header
        }
      end

      def update_cookies_from_response(response)
        (response.get_fields('Set-Cookie') || []).each do |raw|
          name_value = raw.to_s.split(';').first.to_s.strip
          name, value = name_value.split('=', 2)
          @cookies[name] = value if name && !name.empty? && value
        end
      end

      def cookie_header
        @cookies.map { |k, v| "#{k}=#{v}" }.join('; ')
      end

      def log(msg)
        Rails.logger.info("[LaravelSessionRefresher][#{@slug}] #{msg}")
        puts "[LaravelSessionRefresher][#{@slug}] #{msg}"
      end
    end
  end
end
