# Mafia game client.
# Unlike Juwa/GameVault (REST APIs with MD5 signing), Mafia has no public API.
# Player actions (load/cashout/create/reset) must be performed by a Playwright
# browser-automation script running on a remote Windows VPS where AdsPower is
# installed and already logged in to the agent panel at https://mafiaapp.xyz:8781.
#
# This Ruby client wraps that VPS over HTTPS:
#   Rails on Railway  -- HTTPS + X-Patra-Token --> VPS FastAPI listener (port 1098)
#                                                  -> spawns python mafia.py <cmd>
#                                                  -> Playwright clicks buttons
#                                                  -> returns JSON
#
# The interface (method names + return shape) matches Juwa/GameVault so that
# Games::ActionExecutor can dispatch through it without special-casing Mafia.
require 'net/http'
require 'uri'
require 'json'

module Games
  module Mafia
    class Client
      # Long timeout — Playwright + login + CAPTCHA wait can legitimately take minutes.
      # Listener has its own 60-min hard subprocess timeout; mirror it here with margin.
      HTTP_OPEN_TIMEOUT = 20
      HTTP_READ_TIMEOUT = 3700 # ~62 min, slightly longer than listener's 3600

      # Maps listener/script error_code strings to Juwa-style status symbols for
      # consistency with downstream alert/escalation logic. Anything unmapped
      # becomes :unknown_error.
      ERROR_CODE_MAP = {
        'ACCOUNT_EXISTS'           => :account_already_exists,
        'VALIDATION_REJECTED'      => :invalid_params,
        'AGENT_FUNDS_EXHAUSTED'    => :insufficient_agent_balance,
        'LOGIN_FAILED'             => :invalid_agent,
        'ADSPOWER_START_FAILED'    => :system_failed,
        'CAPTCHA_TIMEOUT'          => :system_failed,
        'TIMEOUT'                  => :system_failed,
        'NO_JSON_OUTPUT'           => :system_failed,
        'SUBPROCESS_CRASH'         => :system_failed,
        'CONN_REFUSED'             => :system_failed,
        'NETWORK_ERROR'            => :system_failed,
        'RUNTIME'                  => :system_failed,
        'UNEXPECTED'               => :system_failed
      }.freeze

      class MafiaError < StandardError
        attr_reader :code, :payload
        def initialize(message, code: nil, payload: nil)
          super(message)
          @code    = code
          @payload = payload
        end
      end

      attr_reader :agent_game, :base_url

      def initialize(agent_game)
        @agent_game = agent_game
        @base_url = ENV.fetch('PATRA_VPS_URL', '').to_s.chomp('/')
        @secret   = ENV.fetch('PATRA_VPS_SECRET', '').to_s
        raise ArgumentError, 'PATRA_VPS_URL not set in environment' if @base_url.blank?
        raise ArgumentError, 'PATRA_VPS_SECRET not set in environment' if @secret.blank?
      end

      # Universal interface — required by Games::ClientRegistry contract.

      def test_connection
        # Lightweight: just run the login command. If we can reach the dashboard,
        # the VPS, AdsPower, the agent session, and the network are all healthy.
        call_listener('login', {})
        { ok: true, balance: nil, message: 'Mafia VPS reachable; agent session valid' }
      rescue MafiaError => e
        { ok: false, code: e.code, message: e.message }
      rescue StandardError => e
        { ok: false, code: -1, message: "Connection failed: #{e.message}" }
      end

      def agent_balance
        # Mafia's web panel does not expose agent balance via a clean script
        # command. Return shape-compatible stub so ActionExecutor's test paths
        # don't blow up; real agent balance check happens via Telegram alerts
        # inside the Python script when AGENT_FUNDS_EXHAUSTED is hit.
        { 'code' => 0, 'msg' => 'success', 'data' => { 'agent_balance' => nil } }
      end

      def user_balance(user_id:)
        # In this client, "user_id" is the player account (username). Mafia
        # has no separate numeric user_id concept; we echo username through
        # get_user_id, then receive it back here.
        result = call_listener('balance', account: user_id)
        normalize_response(result, balance_key: 'balance')
      end

      def get_user_id(account_name:)
        # Mafia has no numeric user_id. We pass through the username as the
        # user_id so ActionExecutor's existing load_player / cashout_player flow
        # works unchanged.
        {
          'code' => 0,
          'msg'  => 'success',
          'data' => { 'user_id' => account_name }
        }
      end

      def add_user(account:, password:)
        result = call_listener('create', account: account, password: password)
        normalize_response(result)
      end

      def recharge(user_id:, amount:, order_id:)
        # user_id here is actually the username (see get_user_id).
        # Mafia panel accepts only whole-dollar amounts.
        result = call_listener('recharge', account: user_id, amount: amount.to_f)
        normalize_response(result, order_id: order_id)
      end

      def withdraw(user_id:, amount:, order_id:)
        result = call_listener('redeem', account: user_id, amount: amount.to_f)
        normalize_response(result, order_id: order_id)
      end

      def reset_player_password(user_id:, login_pwd:)
        result = call_listener('reset', account: user_id, password: login_pwd)
        normalize_response(result)
      end

      def force_player_offline(user_id:)
        # Not supported via Mafia panel. Return success-shaped stub so
        # callers that broadcast offline to all games don't crash.
        { 'code' => 0, 'msg' => 'not_supported_for_mafia', 'data' => {} }
      end

      private

      # Transforms the FastAPI listener's response shape:
      #   {"status":"success","action":"recharge","player":"x","amount":1,...}
      # into the {"code":0,"msg":"success","data":{...}} shape ActionExecutor
      # and the audit log expect.
      def normalize_response(raw, balance_key: nil, order_id: nil)
        data = raw.is_a?(Hash) ? raw.dup : {}
        data['order_id'] = order_id if order_id
        # Surface balance under the conventional key when applicable.
        if balance_key && raw.is_a?(Hash) && raw.key?(balance_key)
          data['user_balance'] = raw[balance_key]
        end
        {
          'code' => 0,
          'msg'  => raw.is_a?(Hash) ? raw['action'].to_s : 'success',
          'data' => data
        }
      end

      def call_listener(command, payload)
        uri = URI("#{@base_url}/mafia/#{command}")

        req = Net::HTTP::Post.new(uri)
        req['Content-Type']  = 'application/json'
        req['X-Patra-Token'] = @secret
        req.body = (payload.is_a?(Hash) ? payload : {}).to_json

        safe_payload = payload.is_a?(Hash) ? payload.except(:password, 'password') : {}
        Rails.logger.info("[Mafia] POST #{uri} payload=#{safe_payload.to_json}")

        http = Net::HTTP.new(uri.host, uri.port)
        http.use_ssl = (uri.scheme == 'https')
        http.open_timeout = HTTP_OPEN_TIMEOUT
        http.read_timeout = HTTP_READ_TIMEOUT

        response = http.request(req)
        body = response.body.to_s

        Rails.logger.info("[Mafia] response status=#{response.code} body=#{body[0, 400]}")

        parsed =
          begin
            JSON.parse(body)
          rescue JSON::ParserError
            raise MafiaError.new(
              "Non-JSON response from VPS (status=#{response.code}): #{body[0, 200]}",
              code: -1,
              payload: { http_status: response.code.to_i }
            )
          end

        # HTTP 401 = bad secret. HTTP 5xx = listener/script crash.
        if response.code.to_i == 401
          raise MafiaError.new(
            'VPS rejected shared secret (X-Patra-Token mismatch)',
            code: :invalid_token,
            payload: parsed
          )
        end

        if response.code.to_i >= 500
          ec = parsed.is_a?(Hash) ? parsed['error_code'] : nil
          em = parsed.is_a?(Hash) ? parsed['error_message'] : nil
          raise MafiaError.new(
            em.presence || "VPS listener error (HTTP #{response.code})",
            code: ERROR_CODE_MAP[ec] || :system_failed,
            payload: parsed
          )
        end

        # Script returned status=error (422 from listener)
        if parsed.is_a?(Hash) && parsed['status'] == 'error'
          ec = parsed['error_code']
          em = parsed['error_message']
          raise MafiaError.new(
            em.presence || ec.presence || 'Unknown Mafia error',
            code: ERROR_CODE_MAP[ec] || :unknown_error,
            payload: parsed
          )
        end

        parsed
      rescue Net::OpenTimeout, Net::ReadTimeout => e
        raise MafiaError.new(
          "Timeout calling VPS: #{e.message}",
          code: :system_failed,
          payload: { error: e.class.name }
        )
      rescue Errno::ECONNREFUSED, SocketError => e
        raise MafiaError.new(
          "Cannot reach VPS: #{e.message}",
          code: :system_failed,
          payload: { error: e.class.name }
        )
      end
    end
  end
end
