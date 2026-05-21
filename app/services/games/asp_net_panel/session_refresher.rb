require 'net/http'
require 'uri'
require 'cgi'

# Re-logs into a Cluster 1 ASP.NET sweepstakes panel and captures a fresh
# ASP.NET_SessionId cookie. Writes the new cookie to
# agent_game.credentials['asp_session_id'].
#
# Flow (verified by Phase 1a inspection):
#   1. GET BASE_URL/ → server sets ASP.NET_SessionId + returns login form HTML
#   2. Parse HTML for __VIEWSTATE, __VIEWSTATEGENERATOR, __EVENTVALIDATION,
#      and the CAPTCHA image URL (Tools/VerifyImagePage.aspx?...)
#   3. GET CAPTCHA image (with same cookie from step 1)
#   4. Solve CAPTCHA via CapSolver
#   5. POST login form back to BASE_URL/ with all hidden fields + creds +
#      CAPTCHA solution + btnLogin=Login in
#   6. On success, response sets a fresh ASP.NET_SessionId (session rotated on login).
#      Verify success by checking that we DON'T see the login form again in the body.
#
# Retry strategy:
#   - Up to 10 CapSolver attempts (each is a fresh login-page GET → new CAPTCHA → new solve)
#   - After 10 failures, send the next CAPTCHA image to Telegram, wait up to 30 min for human reply
#     - If reply is digits → use as CAPTCHA, attempt login
#     - If reply is a command word → return as command result (caller decides)
#
# Usage:
#   refresher = Games::AspNetPanel::SessionRefresher.new(agent_game)
#   result = refresher.refresh!
#   # result = { ok: true, new_session_id: "abc123...", attempts: 2 } or
#   #          { ok: false, error: "...", command: nil } or
#   #          { ok: false, command: "skip" }  ← human said skip
module Games
  module AspNetPanel
    class SessionRefresher
      USER_AGENT = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 ' \
                   '(KHTML, like Gecko) Chrome/145.0.0.0 Safari/537.36'.freeze

      OPEN_TIMEOUT = 10
      READ_TIMEOUT = 25
      AUTO_RETRY_LIMIT = 10
      REACTIVE_AUTO_RETRY_LIMIT = 3

      # Map slug → BASE_URL (mirrors app/services/games/<slug>/client.rb)
      BASE_URLS = {
        'milky_way'    => 'https://milkywayapp.xyz:8781',
        'fire_kirin'   => 'https://firekirin.xyz:8888',
        'panda_master' => 'https://pandamaster.vip',
        'orion_stars'  => 'https://orionstars.vip:8781'
      }.freeze

      class RefreshError < StandardError; end

      attr_reader :agent_game

      def initialize(agent_game)
        @agent_game = agent_game
        @slug = agent_game.game.slug.to_s
        @base_url = BASE_URLS[@slug] or
          raise RefreshError, "No BASE_URL configured for slug=#{@slug}"
        @username = agent_game.credentials['agent_username'].to_s.strip
        @password = agent_game.credentials['agent_password'].to_s.strip
        raise RefreshError, "Missing agent_username in credentials" if @username.empty?
        raise RefreshError, "Missing agent_password in credentials" if @password.empty?
        @cookies = {}
        @capsolver = Games::CapsolverClient.new
      end

      # Main entry point. Returns hash with :ok and either :new_session_id or :error/:command.
      def refresh!(interactive: true)
        attempts = 0
        retry_limit = interactive ? AUTO_RETRY_LIMIT : REACTIVE_AUTO_RETRY_LIMIT

        retry_limit.times do |i|
          attempts = i + 1
          log("auto attempt #{attempts}/#{retry_limit}")

          begin
            page_html = fetch_login_page
            tokens = extract_form_tokens(page_html)
            captcha_url = extract_captcha_url(page_html)
            captcha_bytes = fetch_captcha_image(captcha_url)
            captcha_text = @capsolver.solve_image_to_text(captcha_bytes, module_name: 'common')
            log("CapSolver returned #{captcha_text.inspect}")

            new_sid = attempt_login(tokens, captcha_text)
            if new_sid
              persist_new_session(new_sid)
              return { ok: true, new_session_id: new_sid, attempts: attempts, fallback: false }
            end
            log("login attempt #{attempts} failed, retrying")
          rescue Games::CapsolverClient::CapsolverError => e
            log("CapSolver error on attempt #{attempts}: #{e.message}")
          rescue StandardError => e
            log("attempt #{attempts} raised #{e.class}: #{e.message}")
          end
        end

        if interactive
          log("all #{retry_limit} auto attempts failed — escalating to Telegram queue")
          human_result = run_telegram_fallback
          return human_result.merge(attempts: attempts) if human_result
          { ok: false, error: "All #{retry_limit} auto attempts failed and no human reply within timeout", attempts: attempts }
        else
          log("auto refresh exhausted #{REACTIVE_AUTO_RETRY_LIMIT} attempts; Telegram fallback skipped (interactive: false)")
          { ok: false, error: "CapSolver exhausted #{REACTIVE_AUTO_RETRY_LIMIT} attempts (reactive mode, Telegram skipped)", attempts: REACTIVE_AUTO_RETRY_LIMIT }
        end
      end

      private

      # ============ Steps ============

      def fetch_login_page
        uri = URI("#{@base_url}/")
        response = http_get(uri, headers: page_headers(referer: @base_url))
        update_cookies_from_response(response)
        unless response.body.to_s.include?('txtLoginName')
          raise RefreshError, "Login page does not contain txtLoginName — site structure changed or wrong URL (body length=#{response.body.to_s.length})"
        end
        response.body.to_s
      end

      def extract_form_tokens(body)
        tokens = {}
        # __VIEWSTATE and __EVENTVALIDATION are required by ASP.NET.
        # __VIEWSTATEGENERATOR is OPTIONAL — some panels (e.g. panda_master)
        # don't emit it in the login form, and ASP.NET still validates the
        # POST as long as __VIEWSTATE and __EVENTVALIDATION are present.
        %w[__EVENTTARGET __EVENTARGUMENT __LASTFOCUS __VIEWSTATE __VIEWSTATEGENERATOR __EVENTVALIDATION].each do |name|
          m = body.match(/id="#{Regexp.escape(name)}"\s+value="([^"]*)"/)
          tokens[name] = m ? m[1] : ''
        end
        if tokens['__VIEWSTATE'].empty?
          raise RefreshError, '__VIEWSTATE missing from login page'
        end
        tokens
      end

      def extract_captcha_url(body)
        # Look for an <img> whose src points at the verify image endpoint.
        m = body.match(/<img[^>]*\bsrc=["']([^"']*VerifyImagePage[^"']*)["']/i)
        raise RefreshError, 'CAPTCHA image (VerifyImagePage) not found in login HTML' unless m
        rel = m[1]
        rel.start_with?('http') ? rel : "#{@base_url}/#{rel.sub(%r{\A/}, '')}"
      end

      def fetch_captcha_image(url)
        uri = URI(url)
        response = http_get(uri, headers: image_headers(referer: "#{@base_url}/"))
        update_cookies_from_response(response)
        bytes = response.body.to_s
        raise RefreshError, "CAPTCHA image empty (HTTP #{response.code})" if bytes.bytesize < 100
        bytes
      end

      # Attempts a login POST with the given CAPTCHA text. Returns new session
      # id on success, nil on bad-creds/bad-captcha failure. Raises on unexpected.
      def attempt_login(tokens, captcha_text)
        form_params = {
          '__EVENTTARGET' => tokens['__EVENTTARGET'],
          '__EVENTARGUMENT' => tokens['__EVENTARGUMENT'],
          '__LASTFOCUS' => tokens['__LASTFOCUS'],
          '__VIEWSTATE' => tokens['__VIEWSTATE'],
          '__EVENTVALIDATION' => tokens['__EVENTVALIDATION'],
          'txtLoginName' => @username,
          'txtLoginPass' => @password,
          'txtVerifyCode' => captcha_text,
          'btnLogin' => 'Login in'
        }
        # Only include __VIEWSTATEGENERATOR if the page actually emitted it.
        # Sending an empty VSG can cause ASP.NET to reject the POST.
        unless tokens['__VIEWSTATEGENERATOR'].to_s.empty?
          form_params['__VIEWSTATEGENERATOR'] = tokens['__VIEWSTATEGENERATOR']
        end
        body = URI.encode_www_form(form_params)

        uri = URI("#{@base_url}/")
        response = http_post(uri, body, headers: page_headers(referer: @base_url).merge(
          'Origin' => @base_url,
          'Content-Type' => 'application/x-www-form-urlencoded'
        ))
        update_cookies_from_response(response)

        body_text = response.body.to_s
        # On success the server typically redirects (302) or returns a different page WITHOUT the login form.
        # On failure the login form re-renders (still contains txtLoginName + an error message).
        if body_text.include?('txtLoginName')
          # Still on login page → failed. Log the visible error if present.
          err_msg = extract_login_error(body_text)
          log("login form re-rendered after POST → failure reason=#{err_msg.inspect}")
          return nil
        end

        new_sid = @cookies['ASP.NET_SessionId']
        raise RefreshError, "Login appeared successful but no ASP.NET_SessionId cookie in response" if new_sid.to_s.empty?
        new_sid
      end

      def extract_login_error(body)
        # Look for known JavaScript error strings injected on failed login.
        %w[errorNamePasswrd emptyVerifyCode errorPasswordTooLong errorVerifyCode].each do |label|
          m = body.match(/#{Regexp.escape(label)}:\s*"([^"]+)"/)
          return "#{label}: #{m[1]}" if m
        end
        'unknown reason (login form re-rendered without recognized error label)'
      end

      # ============ Telegram fallback ============

      def run_telegram_fallback
        queue = Games::TelegramCaptchaQueue.new(slug: @slug)

        page_html = fetch_login_page
        tokens = extract_form_tokens(page_html)
        captcha_url = extract_captcha_url(page_html)
        captcha_bytes = fetch_captcha_image(captcha_url)

        alert = queue.send_captcha_alert(image_bytes: captcha_bytes)
        reply = queue.poll_for_reply(alert_sent_at: alert[:sent_at], timeout: 30 * 60)

        return nil if reply.nil?

        if reply[:type] == :command
          log("human command received: #{reply[:value]}")
          queue.send_text("Got command '#{reply[:value]}' — refresh for #{@slug} aborted, no action taken.")
          return { ok: false, command: reply[:value], error: "Human aborted via command '#{reply[:value]}'" }
        end

        # Digits — attempt login once with the human's solution
        captcha_text = reply[:value]
        log("attempting login with human-provided CAPTCHA #{captcha_text.inspect}")
        new_sid = attempt_login(tokens, captcha_text)
        if new_sid
          persist_new_session(new_sid)
          queue.send_text("✅ #{@slug} session refreshed via human-solved CAPTCHA.")
          return { ok: true, new_session_id: new_sid, fallback: true }
        else
          queue.send_text("❌ Login failed even with human-solved CAPTCHA for #{@slug}. Check credentials.")
          return { ok: false, error: 'Login failed with human-provided CAPTCHA' }
        end
      rescue StandardError => e
        log("Telegram fallback raised #{e.class}: #{e.message}")
        { ok: false, error: "Telegram fallback failed: #{e.class}: #{e.message}" }
      end

      # ============ Persistence ============

      def persist_new_session(new_sid)
        @agent_game.credentials = @agent_game.credentials.merge('asp_session_id' => new_sid)
        @agent_game.save!
        log("persisted new asp_session_id (length=#{new_sid.length})")
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

      def page_headers(referer:)
        {
          'User-Agent' => USER_AGENT,
          'Accept' => 'text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,image/apng,*/*;q=0.8',
          'Accept-Language' => 'en-US,en;q=0.9',
          'Sec-Ch-Ua' => '"Google Chrome";v="145", "Not.A/Brand";v="8", "Chromium";v="145"',
          'Sec-Ch-Ua-Mobile' => '?0',
          'Sec-Ch-Ua-Platform' => '"Windows"',
          'Sec-Fetch-Dest' => 'document',
          'Sec-Fetch-Mode' => 'navigate',
          'Sec-Fetch-Site' => 'same-origin',
          'Upgrade-Insecure-Requests' => '1',
          'Referer' => referer,
          'Cookie' => cookie_header
        }.reject { |_, v| v.to_s.empty? }
      end

      def image_headers(referer:)
        {
          'User-Agent' => USER_AGENT,
          'Accept' => 'image/avif,image/webp,image/apng,image/*,*/*;q=0.8',
          'Accept-Language' => 'en-US,en;q=0.9',
          'Sec-Fetch-Dest' => 'image',
          'Sec-Fetch-Mode' => 'no-cors',
          'Sec-Fetch-Site' => 'same-origin',
          'Referer' => referer,
          'Cookie' => cookie_header
        }.reject { |_, v| v.to_s.empty? }
      end

      def update_cookies_from_response(response)
        set_cookies = response.get_fields('Set-Cookie') || []
        set_cookies.each do |raw|
          name_value = raw.to_s.split(';').first.to_s.strip
          name, value = name_value.split('=', 2)
          @cookies[name] = value if name && !name.empty? && value
        end
      end

      def cookie_header
        @cookies.map { |k, v| "#{k}=#{v}" }.join('; ')
      end

      def log(msg)
        Rails.logger.info("[SessionRefresher][#{@slug}] #{msg}")
        puts "[SessionRefresher][#{@slug}] #{msg}"  # also print so rake task shows progress
      end
    end
  end
end
