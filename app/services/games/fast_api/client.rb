# FastAPI spec base client. Used by Vblink, Ultra Panda, and any other game
# that follows the appid+timestamp+sign auth pattern from the FastAPI docs.
# Subclasses override env_app_id, env_app_secret, env_agent_account, env_agent_password.
require 'net/http'
require 'uri'
require 'digest'
require 'json'

module Games
  module FastApi
    class Client
      REQUEST_TIMEOUT = 15

      # Per FastAPI spec status code dictionary
      STATUS_CODES = {
        200 => 'Success',
        1   => 'New User Is Created',
        2   => 'User Does Not Exist',
        3   => 'Parameter Error',
        4   => 'Invalid Signature',
        5   => 'Agent Ban',
        6   => 'Account length error',
        7   => 'Account format error',
        8   => 'Password length error',
        9   => 'Password format error',
        10  => 'Requestid Used',
        11  => 'Unknown Database Error',
        12  => 'User Already Exist',
        13  => 'Top Up Fail',
        14  => 'Insufficient Credit',
        15  => 'Withdrawal Failed',
        16  => 'Get Balance Failed',
        17  => 'Operations are Not Allowed In The Game',
        18  => 'System Is Under Maintenance',
        19  => 'The Requested Address Does Not Exist',
        20  => 'Password error',
        21  => 'Agent Name Or Password error',
        22  => 'Platform Not Configured'
      }.freeze

      class FastApiError < StandardError
        attr_reader :code, :payload
        def initialize(code, message, payload = nil)
          super(message)
          @code = code
          @payload = payload
        end
      end

      attr_reader :agent_game, :base_url

      def initialize(agent_game)
        @agent_game = agent_game
        @base_url = (agent_game.game&.api_base_url.presence || default_base_url).chomp('/')
        validate_credentials!
      end

      # === Universal interface methods ===

      def test_connection
        # FastAPI doesn't have a true 'agent balance' endpoint without login.
        # Use a low-impact call: agent_login returns balance.
        result = agent_login
        balance = result.is_a?(Hash) ? result.dig('data', 'balance') : nil
        { ok: true, balance: balance.to_s, message: 'Connected successfully' }
      rescue FastApiError => e
        { ok: false, code: e.code, message: e.message }
      rescue StandardError => e
        { ok: false, code: -1, message: "Connection failed: #{e.message}" }
      end

      def agent_balance
        result = agent_login
        { ok: true, agent_balance: result.dig('data', 'balance').to_s, code: 200, message: 'Success' }
      rescue FastApiError => e
        { ok: false, agent_balance: nil, code: e.code, message: e.message }
      end

      def add_user(account:, password:)
        # /fast/user/create
        result = post('/fast/user/create', {
          account: account.to_s,
          passwd: password.to_s
        })

        # Verification net — same pattern as Juwa + GameVault
        begin
          verify = user_balance_raw(account: account)
          if verify['code'].to_i == 2
            raise FastApiError.new(-1, "FastAPI add_user reported success but user '#{account}' not found after creation", { add_response: result, verify_response: verify })
          end
        rescue FastApiError
          raise
        rescue StandardError => e
          Rails.logger.warn("[FastApi] Verification step failed for '#{account}': #{e.class}: #{e.message}")
        end

        result
      end

      def get_user_id(account_name:)
        # FastAPI doesn't expose a separate user_id — account is the identifier.
        # Return a shape compatible with ActionExecutor: { 'data' => { 'user_id' => account_name } }
        { 'code' => 200, 'msg' => 'Success', 'data' => { 'user_id' => account_name } }
      end

      def user_balance(user_id:)
        # ActionExecutor passes user_id; for FastAPI that IS the account name.
        body = post('/fast/user/balance', { account: user_id.to_s })
        data = body['data']
        if data.is_a?(Hash) && data['user_balance'].nil? && data['balance'].present?
          body = body.merge('data' => data.merge('user_balance' => data['balance']))
        end
        body
      end

      def recharge(user_id:, amount:, order_id:)
        post('/fast/user/deposit', {
          requestid: order_id.to_s.gsub(/[^a-zA-Z0-9]/, ''),
          account: user_id.to_s,
          amount: amount.to_s
        })
      end

      def withdraw(user_id:, amount:, order_id:)
        post('/fast/user/withdrawal', {
          requestid: order_id.to_s.gsub(/[^a-zA-Z0-9]/, ''),
          account: user_id.to_s,
          amount: amount.to_s
        })
      end

      def reset_player_password(user_id:, login_pwd:)
        post('/fast/user/resetPasswd', {
          account: user_id.to_s,
          new_passwd: login_pwd.to_s
        })
      end

      def force_player_offline(user_id:)
        # FastAPI spec doesn't define a player_offline endpoint.
        # Return a graceful response so the universal interface contract holds.
        { 'code' => 19, 'msg' => 'The Requested Address Does Not Exist', 'data' => nil }
      end

      private

      # === Subclass overrides ===

      def default_base_url
        raise NotImplementedError, 'Subclass must define default_base_url'
      end

      def env_app_id
        raise NotImplementedError, 'Subclass must define env_app_id'
      end

      def env_app_secret
        raise NotImplementedError, 'Subclass must define env_app_secret'
      end

      def env_agent_account
        ''
      end

      def env_agent_password
        ''
      end

      def app_id
        agent_game.credentials['app_id'].presence || env_app_id
      end

      def app_secret
        agent_game.credentials['app_secret'].presence || env_app_secret
      end

      def agent_account
        agent_game.credentials['agent_account'].presence || env_agent_account
      end

      def agent_password
        agent_game.credentials['agent_password'].presence || env_agent_password
      end

      def validate_credentials!
        raise ArgumentError, 'Missing app_id' if app_id.blank?
        raise ArgumentError, 'Missing app_secret' if app_secret.blank?
      end

      # === Internal helpers ===

      def user_balance_raw(account:)
        post('/fast/user/balance', { account: account.to_s }, raise_on_error: false)
      end

      def agent_login
        return @agent_login_result if @agent_login_result

        params = {
          requestid: generate_request_id,
          account: agent_account,
          passwd: agent_password
        }
        @agent_login_result = post('/fast/agent/login', params, skip_appsecret: true)
      end

      def generate_request_id
        SecureRandom.alphanumeric(32)
      end

      def generate_signature(params, include_appsecret: true)
        sorted = params.reject { |k, _| k.to_s == 'sign' }.sort.to_h
        str = sorted.map { |k, v| "#{k}=#{v}" }.join('&')
        str += app_secret if include_appsecret
        Digest::MD5.hexdigest(str)
      end

      def post(path, params, raise_on_error: true, skip_appsecret: false)
        url = URI("#{base_url}#{path}")
        timestamp = (Time.now.to_f * 1000).to_i.to_s
        requestid = params[:requestid] || generate_request_id

        body = {
          appid: app_id,
          timestamp: timestamp,
          requestid: requestid
        }.merge(params)
        body.delete(:appid) if skip_appsecret  # agent login doesn't use appid

        body[:sign] = generate_signature(body, include_appsecret: !skip_appsecret)

        Rails.logger.info("[FastApi] POST #{path} (app_id=#{app_id}, ts=#{timestamp})")

        response = Net::HTTP.start(url.host, url.port, use_ssl: url.scheme == 'https',
                                   read_timeout: REQUEST_TIMEOUT, open_timeout: REQUEST_TIMEOUT) do |http|
          req = Net::HTTP::Post.new(url.request_uri)
          req.set_form_data(body.transform_values(&:to_s))
          req['Content-Type'] = 'application/x-www-form-urlencoded'
          http.request(req)
        end

        parse_response(response, raise_on_error: raise_on_error)
      rescue Net::OpenTimeout, Net::ReadTimeout => e
        raise FastApiError.new(-1, "Request timeout: #{e.message}")
      rescue FastApiError
        raise
      rescue StandardError => e
        Rails.logger.error("[FastApi] Network error: #{e.class} - #{e.message}")
        raise
      end

      def parse_response(response, raise_on_error: true)
        unless response.is_a?(Net::HTTPSuccess)
          raise FastApiError.new(response.code.to_i, "HTTP #{response.code}: #{response.body.to_s[0..200]}")
        end

        body = JSON.parse(response.body)
        code = body['code'].to_i

        if code != 200 && code != 1 && raise_on_error
          message = STATUS_CODES[code] || body['msg'] || 'Unknown FastAPI error'
          raise FastApiError.new(code, message, body)
        end

        body
      rescue JSON::ParserError => e
        raise FastApiError.new(-2, "Invalid JSON response: #{e.message}")
      end
    end
  end
end
