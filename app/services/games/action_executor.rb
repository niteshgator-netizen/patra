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

    def check_player_balance(game_username:)
      client = client_for(agent_game)
      user_lookup = client.get_user_id(account_name: game_username)
      user_id = user_lookup.dig('data', 'user_id')
      return nil if user_id.blank?

      result = client.user_balance(user_id: user_id)
      result.dig('data', 'user_balance')
    end

    private

    def client_for(ag)
      case ag.game.slug
      when 'game_vault'
        Games::GameVault::Client.new(ag)
      else
        raise "Game #{ag.game.slug} not yet integrated"
      end
    end

    def execute_in_audit(action)
      result = yield
      action.update!(
        status: 'success',
        api_response_code: result['code'],
        api_response_message: result['msg'],
        api_response_body: result,
        executed_at: Time.current
      )
      agent_game.mark_used!
      agent_game.reset_failures! if agent_game.failure_count > 0
      { ok: true, action: action, response: result }
    rescue Games::GameVault::Client::GameVaultError => e
      action.update!(
        status: 'failed',
        api_response_code: e.code,
        api_response_message: e.message,
        api_response_body: e.payload || {},
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
  end
end
