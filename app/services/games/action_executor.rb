# Wraps API calls in audit logging + idempotency.
# Every load/cashout MUST go through this service, never directly to the Client.

module Games
  class ActionExecutor
    class IdempotencyError < StandardError; end

    attr_reader :agent_game, :contact, :conversation

    def initialize(agent_game:, contact: nil, conversation: nil)
      @agent_game = agent_game
      @contact = contact
      @conversation = conversation
    end

    def add_player(game_username:, password: nil, metadata: {}, order_id: nil)
      order_id ||= GameAction.generate_order_id(prefix: 'addusr')
      password ||= SecureRandom.alphanumeric(8).downcase

      existing = GameAction.find_by(account_id: agent_game.account_id, order_id: order_id)
      raise IdempotencyError, "Order #{order_id} already exists" if existing

      action = GameAction.create!(
        account: agent_game.account,
        agent_game: agent_game,
        contact: contact,
        conversation: conversation,
        action_type: 'add_player',
        order_id: order_id,
        game_username: game_username,
        amount: 0,
        metadata: metadata.merge(password: password),
        status: 'pending'
      )

      result = execute_in_audit(action) do
        client = client_for(agent_game)
        result = client.add_user(account: game_username, password: password)
        action.update!(metadata: action.metadata.merge(password: password))
        result
      end

      if result[:ok]
        sleep(1)
        unless player_exists_after_create?(game_username)
          Rails.logger.error(
            "[ActionExecutor] SILENT FAIL: add_player said OK but check_balance failed for #{game_username} on #{agent_game.game.slug}"
          )
          mark_add_player_verification_failed!(result[:action])
          return {
            ok: false,
            action: result[:action],
            error: 'Account creation reported success but verification failed — account may not exist',
            code: 'silent_fail'
          }
        end

        Rails.logger.info(
          "[ActionExecutor] VERIFIED: #{game_username} exists on #{agent_game.game.slug}"
        )
        result[:password] = password
      end

      result
    end

    def load_player(game_username:, amount:, payment_method: nil, payment_handle: nil, metadata: {}, order_id: nil)
      order_id ||= GameAction.generate_order_id(prefix: 'load')

      # Idempotency check — same order_id can't be re-executed
      existing = GameAction.find_by(account_id: agent_game.account_id, order_id: order_id)
      raise IdempotencyError, "Order #{order_id} already exists with status #{existing.status}" if existing

      action = GameAction.create!(
        account: agent_game.account,
        agent_game: agent_game,
        contact: contact,
        conversation: conversation,
        action_type: 'load',
        order_id: order_id,
        game_username: game_username,
        amount: amount,
        payment_method: payment_method,
        payment_handle: payment_handle,
        metadata: metadata,
        status: 'pending'
      )

      execute_in_audit(action) do
        client = client_for(agent_game)
        # Look up user_id from username
        user_lookup = client.get_user_id(account_name: game_username)
        user_id = user_lookup.dig('data', 'user_id')
        raise "Could not find player ID for username #{game_username}" if user_id.blank?

        action.update!(game_user_id: user_id.to_s)

        # Execute recharge
        client.recharge(user_id: user_id, amount: amount.to_s, order_id: order_id)
      end
    end

    def cashout_player(game_username:, amount:, payment_method: nil, metadata: {}, order_id: nil)
      order_id ||= GameAction.generate_order_id(prefix: 'cash')

      existing = GameAction.find_by(account_id: agent_game.account_id, order_id: order_id)
      raise IdempotencyError, "Order #{order_id} already exists with status #{existing.status}" if existing

      action = GameAction.create!(
        account: agent_game.account,
        agent_game: agent_game,
        contact: contact,
        conversation: conversation,
        action_type: 'cashout',
        order_id: order_id,
        game_username: game_username,
        amount: amount,
        payment_method: payment_method,
        metadata: metadata,
        status: 'pending'
      )

      execute_in_audit(action) do
        client = client_for(agent_game)
        user_lookup = client.get_user_id(account_name: game_username)
        user_id = user_lookup.dig('data', 'user_id')
        raise "Could not find player ID for username #{game_username}" if user_id.blank?

        action.update!(game_user_id: user_id.to_s)

        client.withdraw(user_id: user_id, amount: amount.to_s, order_id: order_id)
      end
    end

    # Reset a player's password on the game panel.
    # Mirrors the load_player/cashout_player pattern: resolve user_id from username,
    # call the universal client interface (client.reset_player_password),
    # audit in GameAction, surface failures via record_failure! + Telegram.
    #
    # Used by ConversationOrchestrator when customer asks to reset their password.
    # The new_password is supplied by the caller (orchestrator generates it).
    def reset_player_password(game_username:, new_password:, metadata: {}, order_id: nil)
      order_id ||= GameAction.generate_order_id(prefix: 'reset')

      existing = GameAction.find_by(account_id: agent_game.account_id, order_id: order_id)
      raise IdempotencyError, "Order #{order_id} already exists with status #{existing.status}" if existing

      action = GameAction.create!(
        account: agent_game.account,
        agent_game: agent_game,
        contact: contact,
        conversation: conversation,
        action_type: 'reset_password',
        order_id: order_id,
        game_username: game_username,
        metadata: metadata,
        status: 'pending'
      )

      execute_in_audit(action) do
        client = client_for(agent_game)
        user_lookup = client.get_user_id(account_name: game_username)
        user_id = user_lookup.dig('data', 'user_id')
        raise "Could not find player ID for username #{game_username}" if user_id.blank?

        action.update!(game_user_id: user_id.to_s)

        # Universal client interface — all clients implement reset_player_password(user_id:, login_pwd:).
        # Verified working on Mafia/Cluster 2 via Rails smoke test May 19 2026.
        client.reset_player_password(user_id: user_id, login_pwd: new_password)
      end
    end

    def check_player_balance(game_username:)
      client = client_for(agent_game)
      user_lookup = client.get_user_id(account_name: game_username)
      user_id = user_lookup.dig('data', 'user_id')
      return nil if user_id.blank?

      result = client.user_balance(user_id: user_id)
      result.dig('data', 'user_balance')
    end

    def player_exists_after_create?(game_username)
      !check_player_balance(game_username: game_username).nil?
    rescue Encoding::CompatibilityError => e
      Rails.logger.warn(
        "[ActionExecutor] player_exists_after_create? encoding error for #{game_username}: #{e.class}: #{e.message}"
      )
      false
    rescue StandardError => e
      Rails.logger.warn(
        "[ActionExecutor] player_exists_after_create? failed for #{game_username}: #{e.class}: #{e.message}"
      )
      false
    end

    def mark_add_player_verification_failed!(action)
      return unless action

      action.update!(
        status: 'failed',
        api_response_code: 'silent_fail',
        api_response_message: 'Account creation reported success but verification failed — account may not exist',
        executed_at: Time.current
      )
      agent_game.record_failure!
    end

    private

    def client_for(ag)
      client = Games::ClientRegistry.client_for(ag)
      raise "Game #{ag.game.slug} not yet integrated" unless client
      client
    end

    def execute_in_audit(action)
      result = sanitize_for_db(yield)
      action.update!(
        status: 'success',
        api_response_code: result['code'],
        api_response_message: result['msg'],
        api_response_body: sanitize_for_db(result),
        executed_at: Time.current
      )
      agent_game.mark_used!
      agent_game.reset_failures! if agent_game.failure_count > 0
      { ok: true, action: action, response: result }
    rescue Games::GameVault::Client::GameVaultError, Games::Juwa::Client::JuwaError,
           Games::FastApi::Client::FastApiError, Games::ClientError => e
      action.update!(
        status: 'failed',
        api_response_code: e.code,
        api_response_message: e.message,
        api_response_body: sanitize_for_db(e.payload || {}),
        executed_at: Time.current
      )
      agent_game.record_failure!
      { ok: false, action: action, error: e.message, code: e.code }
    rescue StandardError => e
      action.update!(
        status: 'failed',
        api_response_message: e.message,
        executed_at: Time.current
      )
      agent_game.record_failure!
      { ok: false, action: action, error: e.message, code: -1 }
    end

    def sanitize_for_db(obj)
      case obj
      when String
        obj.encode('UTF-8', invalid: :replace, undef: :replace, replace: '?')
      when Hash
        obj.transform_values { |v| sanitize_for_db(v) }
      when Array
        obj.map { |v| sanitize_for_db(v) }
      else
        obj
      end
    end
  end
end
