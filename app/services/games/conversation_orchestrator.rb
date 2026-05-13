# Orchestrates the full game-related conversation flow.
# Called from reply_service.rb. Returns nil to let normal Bella handle the turn,
# or { reply:, labels: } when this orchestrator handled the intent.

module Games
  class ConversationOrchestrator
    attr_reader :account, :contact, :conversation, :messages

    def initialize(account:, contact:, conversation:, messages:)
      @account = account
      @contact = contact
      @conversation = conversation
      @messages = messages
    end

    # Main entrypoint. Returns nil if this orchestrator doesn't apply.
    def handle
      return nil unless account && contact

      latest_text = latest_customer_text
      return nil if latest_text.blank?

      intent = Games::IntentDetector.detect(latest_text)
      return nil if intent.nil?

      case intent[:intent]
      when :load
        handle_load_intent(intent)
      when :cashout
        handle_cashout_intent(intent)
      when :username_provided
        handle_username_provided(intent)
      end
    rescue StandardError => e
      Rails.logger.error("[ConversationOrchestrator] #{e.class}: #{e.message}\n#{e.backtrace&.first(5)&.join("\n")}")
      nil
    end

    private

    def handle_load_intent(intent)
      ag = pick_agent_game(intent[:game_slug] || 'game_vault')
      return nil unless ag

      username = intent[:game_username] || stored_game_username(ag.game.slug)

      if username.blank?
        return {
          reply: "got it — what's your username on #{ag.game.name}? if you don't have one, sign up here: #{ag.game.player_signup_url}",
          labels: ['needs-username']
        }
      end

      # Auto-execute load (per requirement: loads auto-execute)
      executor = Games::ActionExecutor.new(agent_game: ag, contact: contact, conversation: conversation)
      result = executor.load_player(
        game_username: username,
        amount: intent[:amount],
        payment_method: nil,
        metadata: { source: 'bella_auto', message: latest_customer_text.to_s[0..200] }
      )

      store_game_username(ag.game.slug, username)

      if result[:ok]
        Games::SlackNotifier.load_alert(result[:action])
        {
          reply: "loaded $#{intent[:amount]} to #{username} on #{ag.game.name} — good luck 🎰",
          labels: ['auto-load']
        }
      else
        {
          reply: "couldn't load $#{intent[:amount]} on #{ag.game.name} — #{friendly_error(result)}. a manager will jump in.",
          labels: ['load-failed', 'needs-human']
        }
      end
    end

    def handle_cashout_intent(intent)
      ag = pick_agent_game(intent[:game_slug] || 'game_vault')
      return nil unless ag

      username = intent[:game_username] || stored_game_username(ag.game.slug)
      if username.blank?
        return {
          reply: "got it — what's your username on #{ag.game.name}? need it to process your cashout.",
          labels: ['needs-username']
        }
      end

      deposit_amount = stored_deposit_amount || 5.0
      requested = intent[:amount]
      total_points = intent[:total_points] || requested

      calc = Games::CashoutCalculator.new(
        account: account,
        deposit_amount: deposit_amount,
        requested_amount: requested,
        total_points: total_points
      ).calculate

      if calc.cashout_amount <= 0
        return {
          reply: "you need at least #{calc.min_required ? "$#{calc.min_required}" : '4x'} in play to cashout. #{calc.explanation}",
          labels: ['cashout-not-eligible']
        }
      end

      cr = CashoutRequest.create!(
        account: account,
        agent_game: ag,
        contact: contact,
        conversation: conversation,
        player_name: contact.name,
        game_username: username,
        total_points: total_points,
        cashout_amount: calc.cashout_amount,
        remaining_points: calc.remaining_points,
        tip_amount: intent[:tip_amount] || 0,
        reload_amount: intent[:reload_amount] || 0,
        original_deposit: deposit_amount,
        deposit_payment_method: stored_payment_method,
        cashout_payment_method: nil,
        applied_rules: calc.applied_rules,
        customer_message: latest_customer_text.to_s[0..500],
        status: 'pending'
      )

      Games::SlackNotifier.cashout_alert(cr)

      # Auto-execute withdraw from game (the money still needs cashier approval to actually pay out)
      executor = Games::ActionExecutor.new(agent_game: ag, contact: contact, conversation: conversation)
      withdraw_result = executor.cashout_player(
        game_username: username,
        amount: calc.cashout_amount,
        metadata: { source: 'bella_auto', cashout_request_id: cr.id }
      )

      cr.update(withdraw_action_id: withdraw_result[:action]&.id) if withdraw_result[:action]

      if (intent[:reload_amount] || 0) > 0
        reload_result = executor.load_player(
          game_username: username,
          amount: intent[:reload_amount],
          metadata: { source: 'bella_auto_reload', cashout_request_id: cr.id }
        )
        cr.update(reload_action_id: reload_result[:action]&.id) if reload_result[:action]
      end

      reply_text = "got it — cashing out $#{calc.cashout_amount} for you. #{calc.explanation} a cashier will send the payment shortly."
      reply_text += " keeping $#{intent[:reload_amount]} loaded back on your game." if (intent[:reload_amount] || 0) > 0

      { reply: reply_text, labels: ['cashout-requested', 'cashier-action-needed'] }
    end

    def handle_username_provided(intent)
      return nil unless intent[:game_slug]

      ag = pick_agent_game(intent[:game_slug])
      return nil unless ag

      recent_deposit = recent_unloaded_deposit
      if recent_deposit
        store_game_username(ag.game.slug, intent[:game_username])

        executor = Games::ActionExecutor.new(agent_game: ag, contact: contact, conversation: conversation)
        result = executor.load_player(
          game_username: intent[:game_username],
          amount: recent_deposit[:amount],
          payment_method: recent_deposit[:method],
          metadata: { source: 'bella_auto_after_username', message: latest_customer_text.to_s[0..200] }
        )

        if result[:ok]
          Games::SlackNotifier.load_alert(result[:action])
          return {
            reply: "got it — loaded $#{recent_deposit[:amount]} to #{intent[:game_username]} on #{ag.game.name}. good luck 🎰",
            labels: ['auto-load']
          }
        else
          return {
            reply: "got your username — but couldn't load $#{recent_deposit[:amount]}: #{friendly_error(result)}. a manager will jump in.",
            labels: ['load-failed', 'needs-human']
          }
        end
      end

      store_game_username(ag.game.slug, intent[:game_username])
      { reply: "got it, saved your #{ag.game.name} username as #{intent[:game_username]}.", labels: ['username-saved'] }
    end

    def pick_agent_game(game_slug)
      account.agent_games.joins(:game).where(games: { slug: game_slug }, status: 'active').first
    end

    def latest_customer_text
      return nil unless messages.is_a?(Array)

      last = messages.reverse.find do |m|
        if m.is_a?(Hash)
          role = m[:role] || m['role']
          role.to_s == 'user'
        else
          m.respond_to?(:incoming?) && m.incoming?
        end
      end
      return nil unless last

      if last.is_a?(Hash)
        (last[:content] || last['content']).to_s
      else
        last.content.to_s
      end
    end

    def stored_game_username(game_slug)
      key = "game_username_#{game_slug}"
      (contact.custom_attributes || {})[key]
    end

    def store_game_username(game_slug, username)
      key = "game_username_#{game_slug}"
      attrs = (contact.custom_attributes || {}).merge(key => username)
      contact.update(custom_attributes: attrs)
    end

    def stored_deposit_amount
      (contact.custom_attributes || {})['last_deposit_amount']&.to_f
    end

    def stored_payment_method
      (contact.custom_attributes || {})['last_deposit_method']
    end

    # Looks at the most recent patra_finance_logs entry. If it's a confirmed deposit
    # less than 30 min old and has no matching load action yet, return its details.
    def recent_unloaded_deposit
      logs = (contact.custom_attributes || {})['patra_finance_logs']
      return nil unless logs.is_a?(Array) && logs.any?

      last = logs.last
      return nil unless last.is_a?(Hash)
      return nil unless %w[Confirmed completed].include?(last['status'].to_s)

      time_str = last['recorded_at'] || last['transaction_time']
      recorded = nil
      begin
        recorded = Time.parse(time_str.to_s) if time_str.present?
      rescue ArgumentError
        recorded = nil
      end

      return nil if recorded && recorded < 30.minutes.ago

      amount = last['amount']&.to_s&.gsub(/[^\d.]/, '')&.to_f
      return nil if amount.nil? || amount <= 0

      already_loaded = GameAction
                       .where(account_id: account.id, contact_id: contact.id, action_type: 'load', status: 'success')
                       .where('created_at >= ?', recorded || 1.hour.ago)
                       .where(amount: amount)
                       .exists?
      return nil if already_loaded

      { amount: amount, method: last['platform'] }
    end

    def friendly_error(result)
      code = result[:code]
      case code
      when 5 then "our access got blocked, fixing now"
      when 8 then "couldn't find that player on the game"
      when 6 then "our agent balance is low, fixing now"
      else
        result[:error] || 'something went wrong'
      end
    end
  end
end
