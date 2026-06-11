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
      return blacklist_error if blacklisted_contact?
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

      # Shared-namespace panels (game_vault<->vegas_sweeps, vblink<->ultra_panda)
      # return a DOCUMENTED already-exists code when the player already has the
      # provider account (e.g. created via the sibling skin). Verify the user
      # really exists on the panel, then treat it as success-reuse. Anything
      # ambiguous (unknown code, verification failure) keeps the failure path.
      if !result[:ok] && already_exists_error?(result) && player_exists_after_create?(game_username)
        action = result[:action]
        action&.update!(
          status: 'success',
          api_response_message: "#{result[:error]} - existing account verified, reused",
          metadata: (action.metadata || {}).merge('reused_existing' => true),
          executed_at: Time.current
        )
        agent_game.reset_failures! if agent_game.failure_count > 0
        Rails.logger.info(
          "[ActionExecutor] add_player already-exists on #{agent_game.game.slug} — verified and REUSED for #{game_username}"
        )
        return { ok: true, action: action, response: { 'reused_existing' => true }, reused_existing: true }
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
      return blacklist_error if blacklisted_contact?

      limit_error = amount_limit_error('max_load_amount', amount)
      return limit_error if limit_error

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

      result = execute_in_audit(action) do
        client = client_for(agent_game)
        # Look up user_id from username
        user_lookup = client.get_user_id(account_name: game_username)
        user_id = user_lookup.dig('data', 'user_id')
        raise "Could not find player ID for username #{game_username}" if user_id.blank?

        action.update!(game_user_id: user_id.to_s)

        # Execute recharge
        client.recharge(user_id: user_id, amount: amount.to_s, order_id: order_id)
      end

      check_low_balance_alert(result)
      result
    end

    # skip_approval_gate: ONLY Approvals::AutoResume passes true, after a human
    # has already approved the exact request — otherwise the approved execution
    # would re-trigger the gate forever. All other callers keep the gate.
    def cashout_player(game_username:, amount:, payment_method: nil, metadata: {}, order_id: nil, skip_approval_gate: false)
      return blacklist_error if blacklisted_contact?

      limit_error = amount_limit_error('max_cashout_amount', amount)
      return limit_error if limit_error

      if !skip_approval_gate && Approvals::CashoutApprovalGate.requires_approval?(agent_game.account, amount)
        request = Approvals::CashoutApprovalGate.create_request!(
          account: agent_game.account,
          user: Current.user || agent_game.account.account_users.first&.user,
          amount: amount,
          target: agent_game,
          metadata: metadata.merge(
            player_name: game_username,
            game_name: agent_game.game.name,
            game_username: game_username
          )
        )
        return { ok: false, error: 'Cashout requires approval', code: 'approval_required', approval_request_id: request&.id }
      end

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
      client = Games::ClientRegistry.client_for(agent_game)
      result = client.get_user_id(account_name: game_username)
      result.is_a?(Hash) && result.dig('data', 'user_id').present?
    rescue StandardError, Encoding::CompatibilityError => e
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

    def blacklisted_contact?
      contact.present? && Contacts::BlacklistChecker.blacklisted?(contact)
    end

    def blacklist_error
      { ok: false, error: 'Contact is blacklisted', code: 'blacklisted' }
    end

    def client_for(ag)
      client = Games::ClientRegistry.client_for(ag)
      raise "Game #{ag.game.slug} not yet integrated" unless client
      client
    end

    # True only when this client family DOCUMENTS the code as already-exists
    # (GameVault family: 20, FastApi family: 12). Clients without the method
    # (Juwa, Laravel, ASP.NET panels) keep their original failure behavior.
    def already_exists_error?(result)
      client = client_for(agent_game)
      client.respond_to?(:already_exists_code?) && client.already_exists_code?(result[:code])
    rescue StandardError
      false
    end

    def amount_limit_error(credential_key, amount)
      max = agent_game.credentials.to_h[credential_key.to_s].to_i
      return nil if max <= 0
      return nil unless amount.to_f > max

      { ok: false, error: "Amount $#{amount} exceeds max $#{max} for #{agent_game.game.name}" }
    end

    def check_low_balance_alert(result)
      return unless result[:ok]

      agent_balance = result.dig(:response, 'data', 'agent_balance')
      if agent_balance.blank?
        begin
          bal_result = client_for(agent_game).agent_balance
          agent_balance = bal_result.dig('data', 'agent_balance') if bal_result.is_a?(Hash)
          agent_balance ||= bal_result[:agent_balance] if bal_result.is_a?(Hash)
        rescue StandardError => e
          Rails.logger.warn("[ActionExecutor] low balance check skipped: #{e.class}: #{e.message}")
          return
        end
      end
      return if agent_balance.blank?

      threshold = agent_game.credentials.to_h['low_balance_threshold'].to_i
      return if threshold <= 0

      balance = agent_balance.to_f
      return if balance >= threshold

      safe_telegram do
        Games::TelegramNotifier.low_balance_alert(
          game_name: agent_game.game.name,
          balance: balance,
          threshold: threshold,
          account: agent_game.account
        )
      end
    end

    def safe_telegram
      yield
    rescue StandardError => e
      Rails.logger.error("[ActionExecutor] Telegram call failed: #{e.class}: #{e.message}")
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
      log_money(action, ok: true)
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
      log_money(action, ok: false, code: e.code)
      { ok: false, action: action, error: e.message, code: e.code }
    rescue StandardError => e
      action.update!(
        status: 'failed',
        api_response_message: e.message,
        executed_at: Time.current
      )
      agent_game.record_failure!
      log_money(action, ok: false, code: -1)
      { ok: false, action: action, error: e.message, code: -1 }
    end

    # One greppable line per money movement — BetterStack/log search keys off
    # the [MONEY] tag. Never raises (logging must not break the money path).
    def log_money(action, ok:, code: nil)
      Rails.logger.info(
        "[MONEY] type=#{action.action_type} ok=#{ok} amount=#{action.amount} " \
        "account=#{action.account_id} contact=#{action.contact_id} " \
        "game=#{agent_game.game&.slug} order=#{action.order_id} code=#{code}"
      )
      emit_money_webhook(action, ok: ok)
    rescue StandardError
      nil
    end

    # Customer webhook (Patra Business Settings webhook_url). emit() is a
    # no-op without a URL and only enqueues — no inline network I/O here.
    def emit_money_webhook(action, ok:)
      event = case action.action_type.to_s
              when 'load', 'recharge' then ok ? 'load.success' : 'load.failed'
              when 'cashout' then ok ? 'cashout.executed' : nil
              end
      return if event.nil?

      Patra::WebhookEmitter.emit(
        account: action.account,
        event: event,
        payload: {
          action_id: action.id,
          action_type: action.action_type,
          amount: action.amount.to_f,
          game: agent_game.game&.slug,
          game_username: action.game_username,
          contact_id: action.contact_id,
          order_id: action.order_id
        }
      )
    rescue StandardError
      nil
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
