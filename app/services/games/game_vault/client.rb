require 'digest'
require 'net/http'
require 'uri'

module Games
  module GameVault
    class Client
      class GameVaultError < StandardError
        attr_reader :code, :payload

        def initialize(code, message, payload = {})
          @code = code
          @payload = payload
          super("Game Vault API error #{code}: #{message}")
        end
      end

      STATUS_CODES = {
        0 => 'Success',
        1 => 'Invalid agent ID',
        2 => 'Invalid request parameters',
        3 => 'Invalid token',
        4 => 'Token expired',
        5 => 'Access IP is not in white list',
        6 => 'Insufficient agent balance',
        7 => 'Insufficient user balance',
        8 => 'Invalid user ID',
        9 => 'User account frozen',
        10 => 'User is in game',
        11 => 'Invalid amount',
        12 => 'Recharge failed, please try again later',
        13 => 'Recharge permission denied',
        14 => 'Withdrawal failed, please try again later',
        15 => 'Withdrawal amount exceeds daily limit',
        16 => 'Withdrawal under review',
        17 => 'Withdrawal permission denied',
        18 => 'Account name format error (must contain letters, numbers, and underscores)',
        19 => 'Agent does not have register user permission',
        20 => 'Account name already exists',
        21 => 'System failed',
        22 => 'Number of register IPs exceeds the upper limit',
        23 => 'Password must be 6 to 32 characters',
        400 => 'Parameter error'
      }.freeze

      DEFAULT_BASE_URL = 'https://apius.gamevault999.com'
      REQUEST_TIMEOUT = 15 # seconds

      attr_reader :agent_game, :base_url

      def initialize(agent_game)
        @agent_game = agent_game
        @base_url = (agent_game.game&.api_base_url.presence || DEFAULT_BASE_URL).chomp('/')
        validate_credentials!
      end

      # === Read-only endpoints (SAFE) ===

      def agent_balance
        post('/api/external/agentBalance', {})
      end

      def user_balance(user_id:)
        post('/api/external/userBalance', { user_id: user_id.to_s })
      end

      def get_user_id(account_name:)
        post('/api/external/getUserID', { account_name: account_name.to_s })
      end

      def low_deposit_users(query_date:, page: 1, page_size: 20)
        post('/api/external/external/getLowDepositUsers', {
          query_date: query_date.to_s,
          page: page.to_i,
          page_size: page_size.to_i
        })
      end

      # === Write endpoints (MOVES MONEY — use with care) ===

      def add_player(account:, login_pwd:)
        post('/api/external/addUser', {
          account: account.to_s,
          login_pwd: login_pwd.to_s
        })
      end

      def recharge(user_id:, amount:, order_id:)
        post('/api/external/recharge', {
          user_id: user_id.to_s,
          amount: amount.to_s,
          order_id: order_id.to_s
        })
      end

      def withdraw(user_id:, amount:, order_id:)
        post('/api/external/withdraw', {
          user_id: user_id.to_s,
          amount: amount.to_s,
          order_id: order_id.to_s
        })
      end

      def reset_player_password(user_id:, login_pwd:)
        post('/api/external/resetPassword', {
          user_id: user_id.to_s,
          login_pwd: login_pwd.to_s
        })
      end

      def force_player_offline(user_id:)
        post('/api/external/playerOffline', { user_id: user_id.to_s })
      end

      # Quick health check — used by "Test Connection" button
      # Returns { ok: true/false, balance:, message: }
      def test_connection
        result = agent_balance
        { ok: true, balance: result.dig('data', 'agent_balance'), message: 'Connected successfully' }
      rescue GameVaultError => e
        { ok: false, code: e.code, message: e.message }
      rescue StandardError => e
        { ok: false, code: -1, message: "Connection failed: #{e.message}" }
      end

      private

      def validate_credentials!
        raise ArgumentError, 'Missing agent_id' if agent_id.blank?
        raise ArgumentError, 'Missing secret_key' if secret_key.blank?
      end

      def agent_id
        agent_game.credentials['agent_id']
      end

      def secret_key
        agent_game.credentials['secret_key']
      end

      def generate_token(timestamp)
        Digest::MD5.hexdigest("#{agent_id}:#{timestamp}:#{secret_key}")
      end

      def post(path, params)
        url = URI("#{base_url}#{path}")
        timestamp = Time.now.to_i.to_s
        token = generate_token(timestamp)

        request_params = params.merge(
          agent_id: agent_id.to_s,
          timestamp: timestamp,
          token: token
        )

        # Stringify keys AND values — Net::HTTP#set_form requires string keys + values
        form_data = request_params.map { |k, v| [k.to_s, v.to_s] }

        Rails.logger.info("[GameVault] POST #{path} (agent_id=#{agent_id}, ts=#{timestamp})")

        response = Net::HTTP.start(url.host, url.port, use_ssl: url.scheme == 'https',
                                   read_timeout: REQUEST_TIMEOUT, open_timeout: REQUEST_TIMEOUT) do |http|
          req = Net::HTTP::Post.new(url.path)
          req.set_form(form_data, 'multipart/form-data')
          http.request(req)
        end

        parse_response(response)
      rescue Net::OpenTimeout, Net::ReadTimeout => e
        raise GameVaultError.new(-1, "Request timeout: #{e.message}")
      rescue StandardError => e
        Rails.logger.error("[GameVault] Network error: #{e.class} - #{e.message}")
        raise
      end

      def parse_response(response)
        unless response.is_a?(Net::HTTPSuccess)
          raise GameVaultError.new(response.code.to_i, "HTTP #{response.code}: #{response.body[0..200]}")
        end

        body = JSON.parse(response.body)
        code = body['code'].to_i

        if code != 0
          message = STATUS_CODES[code] || body['msg'] || 'Unknown error'
          raise GameVaultError.new(code, message, body)
        end

        body
      rescue JSON::ParserError => e
        raise GameVaultError.new(-2, "Invalid JSON response: #{e.message}")
      end
    end
  end
end
