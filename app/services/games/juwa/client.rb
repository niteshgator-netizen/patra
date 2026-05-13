# Juwa game API client.
# Auth: MD5(agent_id:timestamp:secret_key) — same pattern as Game Vault.
# Key difference: recharge/withdraw/balance use user_id, not username.
# So we call getUserID first to resolve username → user_id.
module Games
  module Juwa
    class Client
      BASE_URL    = 'https://ht.juwa777.com'.freeze
      API_PREFIX  = '/api/external'.freeze
      HTTP_TIMEOUT = 15

      RESPONSE_CODES = {
        0  => :success,
        1  => :invalid_agent,
        2  => :invalid_params,
        3  => :invalid_token,
        4  => :token_expired,
        5  => :ip_not_whitelisted,
        6  => :insufficient_agent_balance,
        7  => :insufficient_user_balance,
        8  => :invalid_user_id,
        9  => :account_frozen,
        10 => :user_in_game,
        11 => :invalid_amount,
        12 => :recharge_failed,
        13 => :recharge_permission_denied,
        14 => :withdraw_failed,
        15 => :withdraw_exceeds_daily_limit,
        16 => :withdraw_under_review,
        17 => :withdraw_permission_denied,
        18 => :account_name_format_error,
        19 => :no_register_permission,
        20 => :account_already_exists,
        21 => :system_failed,
        22 => :register_ip_limit_exceeded,
        23 => :invalid_password_length,
        400 => :parameter_error
      }.freeze

      def initialize(agent_id:, secret_key:)
        @agent_id   = agent_id.to_s
        @secret_key = secret_key.to_s
      end

      # Add a new player account.
      # Returns { ok:, user_id:, account_name:, code:, message: }
      def add_user(username:, password:)
        resp = post('addUser', {
          account:   username,
          login_pwd: password
        })
        if resp[:ok]
          { ok: true, user_id: resp.dig(:data, 'user_id'), account_name: resp.dig(:data, 'account_name'), code: 0, message: 'Success' }
        else
          { ok: false, user_id: nil, account_name: nil, code: resp[:code], message: resp[:message] }
        end
      end

      # Resolve username → user_id via getUserID endpoint.
      # Returns user_id string or nil.
      def get_user_id(username:)
        resp = post('getUserID', { account_name: username })
        return nil unless resp[:ok]
        resp.dig(:data, 'user_id')
      end

      # Recharge (load) credits for a player.
      # Resolves username to user_id first.
      # Returns { ok:, amount:, agent_balance:, user_balance:, transaction_id:, code:, message: }
      def recharge(username:, amount:, order_id:)
        user_id = get_user_id(username: username)
        unless user_id
          return { ok: false, amount: amount, code: 8, message: 'Could not resolve user_id for username' }
        end
        resp = post('recharge', {
          user_id:  user_id,
          amount:   amount.to_s,
          order_id: order_id.to_s
        })
        if resp[:ok]
          {
            ok:            true,
            amount:        resp.dig(:data, 'amount'),
            agent_balance: resp.dig(:data, 'agent_balance'),
            user_balance:  resp.dig(:data, 'user_balance'),
            transaction_id: resp.dig(:data, 'transaction_id'),
            code:          0,
            message:       'Success'
          }
        else
          { ok: false, amount: amount, code: resp[:code], message: resp[:message] }
        end
      end

      # Withdraw (cashout) credits for a player.
      # Returns { ok:, amount:, agent_balance:, user_balance:, transaction_id:, code:, message: }
      def withdraw(username:, amount:, order_id:)
        user_id = get_user_id(username: username)
        unless user_id
          return { ok: false, amount: amount, code: 8, message: 'Could not resolve user_id for username' }
        end
        resp = post('withdraw', {
          user_id:  user_id,
          amount:   amount.to_s,
          order_id: order_id.to_s
        })
        if resp[:ok]
          {
            ok:            true,
            amount:        resp.dig(:data, 'amount'),
            agent_balance: resp.dig(:data, 'agent_balance'),
            user_balance:  resp.dig(:data, 'user_balance'),
            transaction_id: resp.dig(:data, 'transaction_id'),
            code:          0,
            message:       'Success'
          }
        else
          { ok: false, amount: amount, code: resp[:code], message: resp[:message] }
        end
      end

      # Get player balance by username.
      # Returns { ok:, user_balance:, code:, message: }
      def user_balance(username:)
        user_id = get_user_id(username: username)
        unless user_id
          return { ok: false, user_balance: nil, code: 8, message: 'Could not resolve user_id for username' }
        end
        resp = post('userBalance', { user_id: user_id })
        if resp[:ok]
          { ok: true, user_balance: resp.dig(:data, 'user_balance'), code: 0, message: 'Success' }
        else
          { ok: false, user_balance: nil, code: resp[:code], message: resp[:message] }
        end
      end

      # Get agent balance.
      # Returns { ok:, agent_balance:, code:, message: }
      def agent_balance
        resp = post('agentBalance', {})
        if resp[:ok]
          { ok: true, agent_balance: resp.dig(:data, 'agent_balance'), code: 0, message: 'Success' }
        else
          { ok: false, agent_balance: nil, code: resp[:code], message: resp[:message] }
        end
      end

      # Reset player password by username.
      def reset_password(username:, new_password:)
        user_id = get_user_id(username: username)
        unless user_id
          return { ok: false, code: 8, message: 'Could not resolve user_id for username' }
        end
        resp = post('resetPassword', { user_id: user_id, login_pwd: new_password })
        { ok: resp[:ok], code: resp[:code], message: resp[:message] }
      end

      # Force player offline by username.
      def player_offline(username:)
        user_id = get_user_id(username: username)
        unless user_id
          return { ok: false, code: 8, message: 'Could not resolve user_id for username' }
        end
        resp = post('playerOffline', { user_id: user_id })
        { ok: resp[:ok], code: resp[:code], message: resp[:message] }
      end

      private

      def post(endpoint, params)
        ts    = Time.now.to_i.to_s
        token = Digest::MD5.hexdigest("#{@agent_id}:#{ts}:#{@secret_key}")

        form = {
          agent_id:  @agent_id,
          timestamp: ts,
          token:     token
        }.merge(params)

        uri  = URI("#{BASE_URL}#{API_PREFIX}/#{endpoint}")
        http = Net::HTTP.new(uri.host, uri.port)
        http.use_ssl    = uri.scheme == 'https'
        http.open_timeout = HTTP_TIMEOUT
        http.read_timeout = HTTP_TIMEOUT

        req = Net::HTTP::Post.new(uri.request_uri)
        req.set_form(form.map { |k, v| [k.to_s, v.to_s] }, 'multipart/form-data')

        response = http.request(req)
        unless response.is_a?(Net::HTTPSuccess)
          Rails.logger.error("[Juwa] HTTP #{response.code} endpoint=#{endpoint}")
          return { ok: false, code: nil, message: "HTTP #{response.code}", data: nil }
        end

        body = JSON.parse(response.body)
        code = body['code'].to_i
        ok   = code == 0

        unless ok
          sym = RESPONSE_CODES[code] || :unknown_error
          Rails.logger.warn("[Juwa] API error #{code} (#{sym}) endpoint=#{endpoint} msg=#{body['msg']}")
        end

        { ok: ok, code: code, message: body['msg'].to_s, data: body['data'] }
      rescue JSON::ParserError => e
        Rails.logger.error("[Juwa] JSON parse error endpoint=#{endpoint}: #{e.message}")
        { ok: false, code: nil, message: 'JSON parse error', data: nil }
      rescue StandardError => e
        Rails.logger.error("[Juwa] #{e.class} endpoint=#{endpoint}: #{e.message}")
        { ok: false, code: nil, message: e.message, data: nil }
      end
    end
  end
end
