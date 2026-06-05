# Orchestrates the full game-related conversation flow.
# Called from reply_service.rb. Returns nil to let normal Bella handle the turn,
# or { reply:, labels: } when this orchestrator handled the intent.

require 'timeout'

module Games
  class ConversationOrchestrator
    attr_reader :account, :contact, :conversation, :messages

    # Bug 1 fix: maps preferred_platform values from
    # players/profile_service.rb's PLATFORM_ALIASES to ClientRegistry game
    # slugs. preferred_platform stores 'milkyway' (no underscore) but
    # agent_games uses 'milky_way' (underscored). This bridges them.
    PREFERRED_PLATFORM_TO_SLUG = {
      'gamevault' => 'game_vault',
      'firekirin' => 'fire_kirin',
      'milkyway' => 'milky_way',
      'pandamaster' => 'panda_master',
      'orionstar' => 'orion_stars',
      'juwa' => 'juwa',
      'juwa2' => 'juwa_2',
      'juwa_2' => 'juwa_2',
      'gameroom' => 'game_room',
      'cash_machine' => 'cash_machine',
      'mr_all_in_one' => 'mr_all_in_one',
      'ultra_panda' => 'ultra_panda',
      'vblink' => 'vblink',
      'vegas_sweeps' => 'vegas_sweeps',
      'mafia' => 'mafia'
    }.freeze

    # Phase 6.5 (May 21 2026): intents AI must never auto-fulfill via game APIs without
    # human review. Full set documented here; only OWNER_ONLY_AUTO_INTENTS are blocked
    # at routing today (IntentDetector does not emit them yet).
    #
    # :cashout (IntentDetector maps redeem/withdraw text → :cashout) is NOT blocked here —
    # production flow uses handle_cashout_intent: Games::TelegramNotifier.cashout_alert for
    # external payout (cashier manual) plus ActionExecutor#cashout_player for in-game redeem.
    FORBIDDEN_AUTO_INTENTS = %w[cashout redeem withdraw refund comp_credit credit_back topup_agent].freeze
    OWNER_ONLY_AUTO_INTENTS = %w[refund comp_credit credit_back topup_agent].freeze

    # Maps RAG real_intent labels → orchestrator intent symbols.
    # Only intents listed here are eligible for RAG cutover routing.
    RAG_TO_INTENT_MAP = {
      'load_deposit'              => :load,
      'load_freeplay'             => :load_freeplay,
      'load_bonus'                => :load_bonus,
      'cashout_redeem'            => :cashout,
      'reset_password'            => :reset_password,
      'payment_handle_request'    => :payment_method_chosen,
      'status_check'              => :status_check,
      'complaint_angry'           => :complaint_angry,
      'tech_issue'                => :tech_issue,
      'balance_check'             => :balance_check,
      'transfer_between_games'    => :transfer_between_games,
      'payment_sent_confirmation' => :payment_sent_confirmation,
      'whats_hitting'             => :whats_hitting,
      'referral'                  => :referral,
      'new_account_reissue'       => :new_account_reissue,
      'redeem_partial_replay'     => :redeem_partial_replay
    }.freeze

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
      combined_text = recent_customer_text
      probe_text = combined_text.presence || latest_text

      Rails.logger.info("[Orchestrator] handle starting account=#{account&.id} contact=#{contact&.id} latest=#{latest_text.to_s[0..100]} combined=#{combined_text.to_s[0..200]}")

      return nil if probe_text.blank?

      # Load-on-answer: if we just asked "where to load?" and the customer named
      # a game, treat it as a load for the verified amount we stored.
      awaiting_amount = conversation&.additional_attributes&.dig('awaiting_load_amount')
      if awaiting_amount.present?
        answered_game = Games::IntentDetector.detect_game(latest_text)
        set_at = conversation.additional_attributes['awaiting_load_set_at']
        fresh = set_at.blank? || (Time.parse(set_at) > 30.minutes.ago rescue true)
        if answered_game.present? && fresh
          Rails.logger.info("[Orchestrator] load-on-answer: game=#{answered_game} amount=#{awaiting_amount}")
          # Clear the flag so it fires once
          attrs = conversation.additional_attributes.dup
          attrs.delete('awaiting_load_amount')
          attrs.delete('awaiting_load_set_at')
          conversation.update_columns(additional_attributes: attrs)
          return handle_load_intent({
            intent: :load,
            amount: awaiting_amount.to_f,
            game_slug: answered_game,
            game_username: nil
          })
        end
      end

      # First check latest message alone — this is what the customer just asked NOW
      latest_intent = Games::IntentDetector.detect(latest_text)

      # Combined fallback ONLY for split-intent loads ("load 20$" + "on juwa") where
      # the latest turn detected as :load but missed the amount/game. Do NOT fall back
      # when latest_intent is nil — that's how greetings get misclassified as cashouts
      # from stale window text. Bug fixed May 21 2026: conv 9 / action 122 case.
      combined_intent = nil
      if latest_intent.is_a?(Hash) && latest_intent[:intent] == :load && latest_intent[:amount].to_f <= 0
        combined_intent = Games::IntentDetector.detect(combined_text)
      end

      intent = latest_intent || combined_intent
      Rails.logger.info("[Orchestrator] intent latest=#{latest_intent.inspect} combined=#{combined_intent.inspect} chosen=#{intent.inspect}")

      # SHADOW MODE (RAG-SHADOW) — compares RAG prediction against regex. No routing impact.
      # Remove or gate behind a feature flag before production cutover.
      begin
        _rag = BellaRag::IntentRetriever.predict(latest_text, account_id: account.id, industry_slug: 'sweepstakes')
        Rails.logger.info("[Orchestrator][RAG-SHADOW] regex=#{intent&.dig(:intent).inspect} rag_intent=#{_rag&.dig(:intent).inspect} rag_conf=#{_rag&.dig(:confidence).inspect}")
      rescue => _rag_err
        Rails.logger.warn("[Orchestrator][RAG-SHADOW] error: #{_rag_err.message}")
      end

      if intent.nil?
        if _rag && _rag[:confidence].to_f >= 0.60
          mapped = RAG_TO_INTENT_MAP[_rag[:intent].to_s]
          if mapped
            intent = { intent: mapped }
            Rails.logger.info("[Orchestrator][RAG-CUTOVER] regex=nil routed to #{mapped} conf=#{_rag[:confidence]}")
          else
            return nil
          end
        else
          return nil
        end
      end

      # Override game_slug with whatever is in the LATEST message — customer may have switched games
      latest_game = Games::IntentDetector.detect_game(latest_text)
      if latest_game && intent.is_a?(Hash)
        intent[:game_slug] = latest_game
        Rails.logger.info("[Orchestrator] overrode game_slug from latest message: #{latest_game}")
      end

      intent_key = intent[:intent].to_s
      if OWNER_ONLY_AUTO_INTENTS.include?(intent_key)
        Rails.logger.info("[Orchestrator] forbidden auto-intent #{intent_key} — escalating to cashier")
        begin
          Games::TelegramNotifier.human_escalation(
            account: account,
            contact: contact,
            reason: "Customer requested #{intent_key} — requires owner/cashier approval",
            conversation: conversation
          )
        rescue StandardError
        end
        return {
          reply: 'got it — let me get a cashier on that for you, one sec',
          labels: %w[needs-human cashier-action-needed]
        }
      end

      case intent[:intent]
      when :load_freeplay
        handle_load_freeplay(intent)
      when :load_bonus
        handle_load_bonus(intent)
      when :load
        handle_load_intent(intent)
      when :cashout
        handle_cashout_intent(intent)
      when :username_provided
        handle_username_provided(intent)
      when :request_account_creation
        handle_account_creation_request(intent)
      when :request_multi_account_creation
        handle_multi_account_creation_request(intent)
      when :payment_method_chosen
        handle_payment_method_chosen(intent)
      when :reset_password
        handle_reset_password_intent(intent)
      when :payment_sent_confirmation
        handle_payment_sent_confirmation(intent)
      when :status_check
        handle_status_check(intent)
      when :complaint_angry
        handle_complaint_angry(intent)
      when :tech_issue
        handle_tech_issue(intent)
      when :balance_check
        handle_balance_check(intent)
      when :transfer_between_games
        handle_transfer_between_games(intent)
      when :whats_hitting
        handle_whats_hitting(intent)
      when :referral
        handle_referral(intent)
      when :redeem_partial_replay
        handle_redeem_partial_replay(intent)
      when :new_account_reissue
        handle_new_account_reissue(intent)
      when :replay_from_balance
        handle_replay_from_balance(intent)
      end
    rescue StandardError => e
      Rails.logger.error("[ConversationOrchestrator] #{e.class}: #{e.message}\n#{e.backtrace&.first(5)&.join("\n")}")
      begin
        Games::TelegramNotifier.api_error(account: account, message: "Orchestrator crashed", details: "#{e.class}: #{e.message}") if account
      rescue StandardError
        # never let notification failure crash anything
      end
      nil
    end

    private

    def handle_load_intent(intent)
      # Sub-route: if RAG or message suggests freeplay/bonus, delegate
      msg_lower = (latest_customer_text || recent_customer_text).to_s.downcase
      if msg_lower.match?(/\b(fp|freeplay|free\s*play|free\s*credit)\b/i)
        return handle_load_freeplay(intent)
      end
      if msg_lower.match?(/\b(bonus|promo|promotion|signup\s*bonus|deposit\s*bonus)\b/i)
        return handle_load_bonus(intent)
      end

      ag = agent_game_for_intent(intent)
      return ag if ag.is_a?(Hash)
      return nil unless ag

      requested_amount = intent[:amount].to_f

      # No explicit amount ("load on juwa") — use the most recent confirmed
      # unloaded payment's amount instead of defaulting to $0.
      payment = nil
      if requested_amount <= 0
        fallback_payment = find_unloaded_confirmed_payment
        if fallback_payment
          requested_amount = fallback_payment[:amount].to_f
          Rails.logger.info("[Orchestrator] amount-less load → using unloaded payment amount=#{requested_amount}")
          payment = fallback_payment
        end
      end

      # PAYMENT GATE: must have confirmed payment matching this amount
      payment ||= find_matching_confirmed_payment(requested_amount)

      unless payment
        # No payment yet — ask for it. Bug 7 fix: pass the default active
        # platform so the reply format matches handle_payment_method_chosen.
        handle_text = active_payment_handle_for_account
        default_platform =
          begin
            active_payment_platforms.first.to_s
          rescue StandardError
            ''
          end
        return {
          reply: payment_request_reply(requested_amount, handle_text, default_platform, ag.game.name),
          labels: ['awaiting-payment']
        }
      end

      # Payment confirmed — now check username
      username = intent[:game_username] || verified_stored_game_username(ag)

      if username.present? && !valid_username?(username)
        return {
          reply: 'what username would you like for your account?',
          labels: ['needs-username']
        }
      end

      if username.blank?
        # Need to ask + offer auto-create
        return {
          reply: "got your $#{requested_amount} payment ✅ what username would you like on #{ag.game.name}? if you've never played, just pick one (3-20 letters/numbers) and i'll set up your account.",
          labels: ['needs-username']
        }
      end

      # Try to load. If username doesn't exist on Game Vault, auto-create it.
      executor = Games::ActionExecutor.new(agent_game: ag, contact: contact, conversation: conversation)

      result = executor.load_player(
        game_username: username,
        amount: requested_amount,
        payment_method: payment[:method],
        metadata: { source: 'bella_auto', payment_id: payment[:id], message: recent_customer_text.to_s[0..200] }
      )

      # Code 8 = user not found → auto-create + retry
      if !result[:ok] && result[:code] == 8
        Rails.logger.info("[Orchestrator] User #{username} not found, auto-creating")
        add_result = add_player_safe(
          executor,
          game_username: username,
          password: password_from_username(username, ag.game.slug)
        )

        unless add_result[:ok]
          failure_response = add_player_failure_response(ag, add_result)
          return failure_response if failure_response

          safe_telegram { Games::TelegramNotifier.load_failed(add_result[:action]) if add_result[:action] }
          safe_telegram do
            Games::TelegramNotifier.human_escalation(
              account: account,
              contact: contact,
              reason: "Failed to create user #{username} on #{ag.game.name}: #{add_result[:error]}",
              conversation: conversation
            )
          end
          return {
            reply: "hit a snag setting up your account — flagged a teammate, they'll get you sorted in a couple minutes.",
            labels: ['account-creation-failed', 'needs-human']
          }
        end

        generated_password = add_result[:password]
        store_game_username(ag.game.slug, username)
        store_game_password(ag.game.slug, generated_password)

        # Retry the load now that user exists
        result = executor.load_player(
          game_username: username,
          amount: requested_amount,
          payment_method: payment[:method],
          metadata: { source: 'bella_auto_after_create', payment_id: payment[:id] }
        )

        if result[:ok]
          mark_payment_loaded(payment[:id], game_slug: ag.game.slug, game_username: username)
          return {
            reply: "created your account! username: #{username}, password: #{generated_password} (save this!) — loaded $#{requested_amount} 🎰",
            labels: ['auto-load', 'new-account-created']
          }
        end
      end

      # First-try result handling
      store_game_username(ag.game.slug, username)

      if result[:ok]
        mark_payment_loaded(payment[:id], game_slug: ag.game.slug, game_username: username)
        {
          reply: "loaded $#{requested_amount} to #{username} on #{ag.game.name} 🎰 good luck!",
          labels: ['auto-load']
        }
      else
        safe_telegram { Games::TelegramNotifier.load_failed(result[:action]) if result[:action] }
        safe_telegram do
          Games::TelegramNotifier.human_escalation(
            account: account,
            contact: contact,
            reason: "Load failed: #{result[:error]} (code #{result[:code]}) for #{username} $#{requested_amount}",
            conversation: conversation
          )
        end
        {
          reply: honest_failure_reply(result, requested_amount, ag.game.name),
          labels: ['load-failed', 'needs-human']
        }
      end
    end

    def handle_load_freeplay(intent = nil)
      game_slug = chosen_game_slug(intent || { intent: :load })

      unless game_slug
        return { reply: 'which game for freeplay?', labels: [] }
      end

      contact = conversation.contact
      if contact.player_tier&.blocked?
        return { reply: "sorry, can't process that right now", labels: [] }
      end

      begin
        game = Game.find_by(slug: game_slug)
        rules = game ? GameRule.find_by(account_id: account.id, game_id: game.id) : nil
      rescue StandardError => e
        Rails.logger.error("[Orchestrator] GameRule lookup failed: #{e.message}")
        rules = nil
      end

      unless rules&.freeplay_enabled
        safe_telegram do
          Games::TelegramNotifier.human_escalation(
            account: account, contact: contact,
            reason: "Freeplay requested on #{game_slug} but not enabled. Contact: #{contact.name}",
            conversation: conversation
          )
        end
        return {
          reply: "freeplay isn't available on #{game_slug} right now",
          labels: ['cashier-action-needed']
        }
      end

      unless rules.freeplay_eligible?(contact)
        return { reply: "freeplay isn't available for your account tier right now", labels: [] }
      end

      begin
        fp_scope = game_actions_for_slug(contact.id, game_slug)
          .where(action_type: 'load', status: 'success')
          .where("metadata->>'freeplay' = 'true'")

        today_count = fp_scope.where('game_actions.created_at >= ?', Time.current.beginning_of_day).count
        week_count = fp_scope.where('game_actions.created_at >= ?', Time.current.beginning_of_week).count

        if today_count >= (rules.freeplay_max_per_day || 1)
          return { reply: 'you already got your freeplay today! try again tomorrow', labels: [] }
        end

        if week_count >= (rules.freeplay_max_per_week || 3)
          return { reply: 'you hit the weekly freeplay limit, resets next week', labels: [] }
        end
      rescue StandardError => e
        Rails.logger.error("[Orchestrator] Freeplay limit check failed: #{e.message}")
      end

      if rules.freeplay_require_deposit_first
        begin
          has_deposit = game_actions_for_slug(contact.id, game_slug)
            .where(action_type: 'load', status: 'success')
            .where("COALESCE(metadata->>'freeplay', 'false') != 'true'")
            .exists?

          unless has_deposit
            return { reply: 'you need at least one deposit before getting freeplay', labels: [] }
          end
        rescue StandardError => e
          Rails.logger.error("[Orchestrator] Deposit-first check failed: #{e.message}")
        end
      end

      fp_amount = contact.player_tier&.override_for('freeplay_amount') || rules.freeplay_amount || 5.0

      begin
        username = find_game_username_for_slug(contact, game_slug)
        unless username
          return {
            reply: "I don't have your #{game_slug} account yet — want me to create one?",
            labels: []
          }
        end

        result = execute_game_api(
          game_slug: game_slug,
          action: 'recharge',
          username: username,
          amount: fp_amount.to_i
        )

        if result[:success]
          begin
            ag = pick_agent_game(game_slug)
            if ag
              GameAction.create!(
                account_id: account.id,
                agent_game_id: ag.id,
                contact_id: contact.id,
                conversation_id: conversation&.id,
                action_type: 'load',
                order_id: GameAction.generate_order_id(prefix: 'fp'),
                game_username: username,
                amount: fp_amount,
                status: 'success',
                metadata: { freeplay: true, source: 'bella_freeplay' },
                executed_at: Time.current
              )
            end
          rescue StandardError => e
            Rails.logger.error("[Orchestrator] Freeplay GameAction log failed: #{e.message}")
          end

          reply_text = rules.format_message(rules.freeplay_message || 'fp loaded ✅', {
            amount: fp_amount.to_s,
            game: game_slug
          })
          { reply: reply_text, labels: [] }
        else
          safe_telegram do
            Games::TelegramNotifier.human_escalation(
              account: account, contact: contact,
              reason: "Freeplay load FAILED on #{game_slug}. Contact: #{contact.name}. Error: #{result[:error]}",
              conversation: conversation
            )
          end
          {
            reply: "couldn't load freeplay right now — let me get someone to help",
            labels: ['cashier-action-needed']
          }
        end
      rescue StandardError => e
        Rails.logger.error("[Orchestrator] Freeplay execution failed: #{e.message}")
        safe_telegram do
          Games::TelegramNotifier.human_escalation(
            account: account, contact: contact,
            reason: "Freeplay error on #{game_slug}: #{e.message}. Contact: #{contact.name}",
            conversation: conversation
          )
        end
        {
          reply: 'having trouble loading that — one sec',
          labels: ['cashier-action-needed']
        }
      end
    end

    def handle_load_bonus(intent = nil)
      game_slug = chosen_game_slug(intent || { intent: :load })

      unless game_slug
        return { reply: 'which game?', labels: [] }
      end

      contact = conversation.contact

      begin
        game = Game.find_by(slug: game_slug)
        rules = game ? GameRule.find_by(account_id: account.id, game_id: game.id) : nil
      rescue StandardError => e
        Rails.logger.error("[Orchestrator] GameRule lookup failed: #{e.message}")
        rules = nil
      end

      unless rules&.deposit_bonus_enabled
        Rails.logger.info("[Orchestrator] No bonus rules for #{game_slug}, falling back to regular load")
        return handle_load_intent(intent || { intent: :load, game_slug: game_slug })
      end

      if rules.deposit_bonus_first_deposit_only
        begin
          has_prior_deposit = game_actions_for_slug(contact.id, game_slug)
            .where(action_type: 'load', status: 'success')
            .where.not(amount: nil)
            .where("COALESCE(metadata->>'freeplay', 'false') != 'true'")
            .exists?

          if has_prior_deposit
            Rails.logger.info('[Orchestrator] Bonus is first-deposit-only, contact already deposited — regular load')
            return handle_load_intent(intent || { intent: :load, game_slug: game_slug })
          end
        rescue StandardError => e
          Rails.logger.error("[Orchestrator] First-deposit check failed: #{e.message}")
        end
      end

      unless rules.deposit_bonus_eligible?(contact)
        Rails.logger.info('[Orchestrator] Contact tier not eligible for bonus — regular load')
        return handle_load_intent(intent || { intent: :load, game_slug: game_slug })
      end

      payment = find_unloaded_confirmed_payment
      unless payment
        return { reply: "send payment first and I'll load with your bonus!", labels: [] }
      end

      deposit_amount = payment[:amount].to_f

      if deposit_amount < (rules.deposit_bonus_min_amount || 0)
        Rails.logger.info("[Orchestrator] Deposit #{deposit_amount} below bonus min #{rules.deposit_bonus_min_amount} — regular load")
        return handle_load_intent(intent || { intent: :load, game_slug: game_slug, amount: deposit_amount })
      end

      bonus_amount = rules.calculate_bonus(deposit_amount)
      total_load = deposit_amount + bonus_amount

      begin
        username = find_game_username_for_slug(contact, game_slug)
        unless username
          return {
            reply: "I don't have your #{game_slug} account — want me to create one?",
            labels: []
          }
        end

        result = execute_game_api(
          game_slug: game_slug,
          action: 'recharge',
          username: username,
          amount: total_load.to_i
        )

        if result[:success]
          begin
            ag = pick_agent_game(game_slug)
            if ag
              GameAction.create!(
                account_id: account.id,
                agent_game_id: ag.id,
                contact_id: contact.id,
                conversation_id: conversation&.id,
                action_type: 'load',
                order_id: GameAction.generate_order_id(prefix: 'bonus'),
                game_username: username,
                amount: total_load,
                status: 'success',
                metadata: {
                  deposit_bonus: true,
                  deposit_amount: deposit_amount,
                  bonus_amount: bonus_amount,
                  payment_id: payment[:id],
                  source: 'bella_bonus'
                },
                executed_at: Time.current
              )
            end
          rescue StandardError => e
            Rails.logger.error("[Orchestrator] Bonus GameAction log failed: #{e.message}")
          end

          mark_payment_loaded(payment[:id], game_slug: game_slug, game_username: username)

          reply_text = rules.format_message(rules.deposit_bonus_message || 'Loaded with {bonus_pct}% bonus ✅', {
            amount: deposit_amount.to_s,
            bonus_pct: (rules.deposit_bonus_percentage || 20).to_s,
            bonus_amount: bonus_amount.to_s,
            total: total_load.to_s,
            game: game_slug
          })
          { reply: reply_text, labels: ['auto-load'] }
        else
          safe_telegram do
            Games::TelegramNotifier.human_escalation(
              account: account, contact: contact,
              reason: "Bonus load FAILED on #{game_slug}. Amount: #{total_load}. Contact: #{contact.name}",
              conversation: conversation
            )
          end
          {
            reply: "couldn't load right now — getting help",
            labels: ['cashier-action-needed']
          }
        end
      rescue StandardError => e
        Rails.logger.error("[Orchestrator] Bonus load failed: #{e.message}")
        safe_telegram do
          Games::TelegramNotifier.human_escalation(
            account: account, contact: contact,
            reason: "Bonus load error: #{e.message}. Contact: #{contact.name}",
            conversation: conversation
          )
        end
        {
          reply: 'having trouble — one sec',
          labels: ['cashier-action-needed']
        }
      end
    end

    def handle_cashout_intent(intent = nil)
      contact = conversation.contact
      game_slug = chosen_game_slug(intent || { intent: :cashout })

      # Check if contact tier is blocked
      if contact.player_tier&.blocked?
        return { reply: "sorry, can't process that right now", labels: [] }
      end

      unless game_slug
        return {
          reply: "which game do you want to cash out from?",
          labels: ['cashier-action-needed']
        }
      end

      # Look up game rules
      rules = nil
      begin
        game = Game.find_by(slug: game_slug)
        rules = game ? GameRule.find_by(account_id: conversation.account_id, game_id: game.id) : nil
      rescue StandardError => e
        Rails.logger.error("[Orchestrator] Cashout GameRule lookup failed: #{e.message}")
      end

      # Check if cashout is enabled
      if rules && !rules.cashout_enabled
        return {
          reply: "cashouts aren't available on #{game_slug} right now",
          labels: []
        }
      end

      # Parse requested amount from message
      requested_amount = nil
      msg = (latest_customer_text || recent_customer_text).to_s
      if msg.match?(/\$?\d+/)
        requested_amount = msg.scan(/\$?(\d+(?:\.\d{1,2})?)/).flatten.first&.to_f
      end

      # Calculate deposit history for multiplier check
      if rules
        begin
          total_deposits = game_actions_for_slug(contact.id, game_slug)
            .where(action_type: 'load', status: 'success')
            .where("COALESCE(metadata->>'freeplay', 'false') != 'true'")
            .sum(:amount).to_f

          total_freeplay = game_actions_for_slug(contact.id, game_slug)
            .where(action_type: 'load', status: 'success')
            .where("metadata->>'freeplay' = ?", 'true')
            .sum(:amount).to_f

          has_real_deposits = (total_deposits - total_freeplay) > 0

          if has_real_deposits
            min_cashout = total_deposits * (rules.cashout_min_multiplier || 4)
            max_cashout = [total_deposits * (rules.cashout_max_multiplier || 10), rules.cashout_max_amount || 250].min
          else
            # Freeplay-only player
            min_cashout = total_freeplay * (rules.cashout_freeplay_multiplier || 5)
            max_cashout = rules.cashout_freeplay_max || 50
          end

          # Validate requested amount
          if requested_amount
            if requested_amount < (rules.cashout_min_amount || 10)
              return {
                reply: "minimum cashout is $#{(rules.cashout_min_amount || 10).to_i}",
                labels: []
              }
            end

            if requested_amount > max_cashout
              return {
                reply: "max cashout is $#{max_cashout.to_i} based on your deposits. #{rules.cashout_rules_text}".strip,
                labels: []
              }
            end
          end

          # If screenshot required
          if rules.cashout_require_screenshot
            has_screenshot = conversation.messages
              .where(message_type: :incoming)
              .order(created_at: :desc)
              .limit(5)
              .any? { |m| m.attachments.any? }

            unless has_screenshot
              return {
                reply: "send me a screenshot of your balance and I'll process the cashout",
                labels: ['cashier-action-needed']
              }
            end
          end

        rescue StandardError => e
          Rails.logger.error("[Orchestrator] Cashout rules validation failed: #{e.message}")
        end
      end

      # All checks passed — escalate to cashier for actual payout
      amount_text = requested_amount ? "$#{requested_amount.to_i}" : "cashout"
      begin
        Games::TelegramNotifier.human_escalation(
          account: account,
          contact: contact,
          reason: "cashout_redeem — Cashout request: #{amount_text} on #{game_slug}. Contact: #{contact.name}",
          conversation: conversation
        )
      rescue StandardError => e
        Rails.logger.error("[Orchestrator] Cashout Telegram escalation failed: #{e.message}")
      end

      {
        reply: requested_amount ? "processing your $#{requested_amount.to_i} cashout on #{game_slug}" : "processing your cashout — one moment",
        labels: %w[cashier-action-needed]
      }
    end

    def handle_username_provided(intent)
      ag = agent_game_for_intent(intent)
      return ag if ag.is_a?(Hash)
      return nil unless ag

      username = intent[:game_username]

      unless valid_username?(username)
        return {
          reply: 'what username would you like for your account?',
          labels: ['needs-username']
        }
      end

      # Check if there's a confirmed payment waiting to be loaded
      recent_payment = find_unloaded_confirmed_payment
      return nil unless recent_payment # No pending action — let normal Bella handle

      executor = Games::ActionExecutor.new(agent_game: ag, contact: contact, conversation: conversation)

      # First try to load — if user doesn't exist, auto-create
      result = executor.load_player(
        game_username: username,
        amount: recent_payment[:amount],
        payment_method: recent_payment[:method],
        metadata: { source: 'bella_username_provided', payment_id: recent_payment[:id] }
      )

      if !result[:ok] && result[:code] == 8
        # User not found — create them
        add_result = add_player_safe(
          executor,
          game_username: username,
          password: password_from_username(username, ag.game.slug)
        )

        unless add_result[:ok]
          failure_response = add_player_failure_response(ag, add_result)
          return failure_response if failure_response

          safe_telegram { Games::TelegramNotifier.load_failed(add_result[:action]) if add_result[:action] }
          safe_telegram do
            Games::TelegramNotifier.human_escalation(
              account: account, contact: contact,
              reason: "Failed to create user #{username}: #{add_result[:error]}",
              conversation: conversation
            )
          end
          return {
            reply: "hit a snag setting up your account — flagged a teammate, they'll get you sorted in a couple minutes.",
            labels: ['account-creation-failed', 'needs-human']
          }
        end

        password = add_result[:password]
        store_game_username(ag.game.slug, username)
        store_game_password(ag.game.slug, password)

        result = executor.load_player(
          game_username: username,
          amount: recent_payment[:amount],
          payment_method: recent_payment[:method],
          metadata: { source: 'bella_username_after_create', payment_id: recent_payment[:id] }
        )

        if result[:ok]
          mark_payment_loaded(recent_payment[:id], game_slug: ag.game.slug, game_username: username)
          return {
            reply: "created your account! username: #{username}, password: #{password} (save this!) — loaded $#{recent_payment[:amount]} 🎰",
            labels: ['auto-load', 'new-account-created']
          }
        end
      end

      store_game_username(ag.game.slug, username)

      if result[:ok]
        mark_payment_loaded(recent_payment[:id], game_slug: ag.game.slug, game_username: username)
        {
          reply: "loaded $#{recent_payment[:amount]} to #{username} on #{ag.game.name} 🎰 good luck!",
          labels: ['auto-load']
        }
      else
        safe_telegram { Games::TelegramNotifier.load_failed(result[:action]) if result[:action] }
        safe_telegram do
          Games::TelegramNotifier.human_escalation(
            account: account, contact: contact,
            reason: "Load failed for #{username} $#{recent_payment[:amount]}: #{result[:error]}",
            conversation: conversation
          )
        end
        {
          reply: honest_failure_reply(result, recent_payment[:amount], ag.game.name),
          labels: ['load-failed', 'needs-human']
        }
      end
    end

    def handle_account_creation_request(intent)
      game_slug = intent[:game_slug]
      if game_slug.blank?
        return {
          reply: "hey! which game you wanna get on? we got #{active_games_list_text}",
          labels: ['needs-game']
        }
      end

      ag = pick_agent_game(game_slug)
      unless ag
        return { reply: unavailable_game_reply(game_slug), labels: ['game-unavailable'] }
      end

      # Check if customer wants to create a DIFFERENT account (replace existing)
      wants_replace = recent_customer_text.to_s.downcase.match?(/\b(diff(erent)?|another|new|change)\b.*\b(one|account|username)\b/) ||
                      recent_customer_text.to_s.downcase.match?(/\b(no|nah|nope|dont|don't)\b.*\b(use|like|want|that)\b/)

      # NO DUPLICATE ACCOUNTS — unless customer asked for a different one
      existing_username = verified_stored_game_username(ag)
      existing_password = existing_username.present? ? stored_game_password(ag.game.slug) : nil
      if existing_username.present? && !wants_replace
        methods_q = payment_methods_question
        reply = if existing_password.present?
          "you already have a #{ag.game.name} account! username: #{existing_username}, password: #{existing_password} 🎰 #{methods_q}"
        else
          "you already have a #{ag.game.name} account: #{existing_username}. #{methods_q}"
        end
        return { reply: reply, labels: ['account-exists', 'awaiting-payment'] }
      end

      # If replace requested, clear stored credentials so we generate fresh ones
      if existing_username.present? && wants_replace
        Rails.logger.info("[Orchestrator] customer requested replacement for #{ag.game.slug} — clearing old credentials from vault")
        clear_game_credentials(ag.game.slug)
      end

      # Check if customer has a confirmed payment waiting
      recent_payment = find_unloaded_confirmed_payment

      unless recent_payment
        # No payment yet — create account first, then ask for payment
        executor = Games::ActionExecutor.new(agent_game: ag, contact: contact, conversation: conversation)
        add_result, auto_username, = attempt_auto_add_player(executor, ag.game.slug)

        failure_response = add_player_failure_response(ag, add_result)
        return failure_response if failure_response

        unless add_result[:ok]
          Rails.logger.error("[Orchestrator] add_player failed for #{ag.game.name} after 2 retries: #{add_result[:error]}")
          safe_telegram do
            Games::TelegramNotifier.human_escalation(
              account: account, contact: contact,
              reason: "Failed to auto-create username on #{ag.game.name}: #{add_result[:error]}",
              conversation: conversation
            )
          end
          return {
            reply: "hit a snag setting up your #{ag.game.name} account — flagged a teammate, they'll get you sorted in a couple minutes.",
            labels: ['account-creation-failed', 'needs-human']
          }
        end

        generated_password = add_result[:password]
        store_game_username(ag.game.slug, auto_username)
        store_game_password(ag.game.slug, generated_password)

        return {
          reply: "all set! your username: #{auto_username}, password: #{generated_password} (save this!) — #{payment_methods_question}",
          labels: ['account-created', 'awaiting-payment']
        }
      end

      # Customer has confirmed payment — create account with auto-generated username
      executor = Games::ActionExecutor.new(agent_game: ag, contact: contact, conversation: conversation)
      add_result, auto_username, = attempt_auto_add_player(
        executor,
        ag.game.slug,
        metadata: { source: 'bella_account_created_with_payment' }
      )

      failure_response = add_player_failure_response(ag, add_result)
      return failure_response if failure_response

      unless add_result[:ok]
        safe_telegram { Games::TelegramNotifier.load_failed(add_result[:action]) if add_result[:action] }
        safe_telegram do
          Games::TelegramNotifier.human_escalation(
            account: account, contact: contact,
            reason: "Failed to auto-create username on #{ag.game.name}: #{add_result[:error]}",
            conversation: conversation
          )
        end
        return {
          reply: "hit a snag creating your account — flagged a teammate, they'll get you set up in a couple minutes.",
          labels: ['account-creation-failed', 'needs-human']
        }
      end

      generated_password = add_result[:password]
      store_game_username(ag.game.slug, auto_username)
      store_game_password(ag.game.slug, generated_password)

      # Load the payment
      result = executor.load_player(
        game_username: auto_username,
        amount: recent_payment[:amount],
        payment_method: recent_payment[:method],
        metadata: { source: 'bella_account_created', payment_id: recent_payment[:id] }
      )

      if result[:ok]
        mark_payment_loaded(recent_payment[:id], game_slug: ag.game.slug, game_username: auto_username)
        {
          reply: "all set! username: #{auto_username}, password: #{generated_password} (save this!) — loaded $#{recent_payment[:amount]} 🎰 good luck!",
          labels: ['auto-load', 'new-account-created']
        }
      else
        safe_telegram { Games::TelegramNotifier.load_failed(result[:action]) if result[:action] }
        safe_telegram do
          Games::TelegramNotifier.human_escalation(
            account: account, contact: contact,
            reason: "Created account #{auto_username} but load failed: #{result[:error]}",
            conversation: conversation
          )
        end
        {
          reply: "created your account! username: #{auto_username}, password: #{generated_password} (save this!) — but hit a snag loading your $#{recent_payment[:amount]}. a teammate will load it in a couple minutes.",
          labels: ['account-created', 'load-failed', 'needs-human']
        }
      end
    end

    def handle_multi_account_creation_request(intent)
      slugs = if intent[:game_slugs] == :all
                account.agent_games.joins(:game).where(status: 'active').pluck('games.slug')
              else
                Array(intent[:game_slugs])
              end
      slugs = slugs.uniq.compact

      if slugs.empty?
        return {
          reply: "hey! which game you wanna get on? we got #{active_games_list_text}",
          labels: ['needs-game']
        }
      end

      replies = []
      labels = ['multi-account-creation']

      slugs.each do |slug|
        result = handle_account_creation_request(intent: :request_account_creation, game_slug: slug)
        next unless result.is_a?(Hash)

        replies << result[:reply] if result[:reply].present?
        labels.concat(Array(result[:labels]))
      end

      {
        reply: replies.presence&.join("\n\n") || "hit a snag setting up your accounts — flagged a teammate, they'll get you sorted shortly.",
        labels: labels.uniq
      }
    end

    GAME_SUFFIX_MAP = {
      'game_vault'      => 'gv',
      'juwa'            => 'jw',
      'juwa_2'          => 'jw2',
      'orion_stars'     => 'os',
      'fire_kirin'      => 'fk',
      'milky_way'       => 'mw',
      'vegas_sweeps'    => 'vs',
      'ultra_panda'     => 'up',
      'cash_frenzy'     => 'cf',
      'panda_master'    => 'pm',
      'river_sweeps'    => 'rs',
      'blue_dragon'     => 'bd',
      'golden_dragon'   => 'gd',
      'vegas_x'         => 'vx',
      'magic_city'      => 'mc',
      'lightning_link'  => 'll',
      'noble_sweeps'    => 'ns',
      'joker_mania'     => 'jm',
      'game_room'       => 'gr',
      'vblink'          => 'vb',
      'golden_treasure' => 'gt',
      'mr_all_in_one'   => 'ma',
      'bit_play'        => 'bp',
      'sirenis'         => 'si',
      'egame'           => 'eg',
      'cash_machine'    => 'cm',
      'spin_city'       => 'sc',
      'mafia'           => 'mf',
      'billion_balls'   => 'bb',
      'yolo'            => 'yo',
      'vegas_roll'      => 'vr'
    }.freeze

    # Slugs whose panels require strong passwords on RESET only (upper+lower+special, 6-12 chars).
    # Verified May 19 2026 against live Mafia panel error message; same Laravel/layui codebase
    # for all 4 Cluster 2 panels, so they share this rule.
    CLUSTER_2_RESET_STRONG_PW = %w[mafia game_room cash_machine mr_all_in_one].freeze

    # Bug fix May 19 2026: Cluster 2 Laravel panels reject usernames with
    # underscores ("letters and numbers only, 5-20 chars"). We use this set
    # to choose the username format in generate_auto_username and to know
    # how to extract the password back out via password_from_username.
    # Same 4 slugs as CLUSTER_2_RESET_STRONG_PW — kept as a separate
    # constant for clarity in case username rules diverge from reset rules.
    CLUSTER_2_SLUGS = %w[mafia game_room cash_machine mr_all_in_one].freeze

    # Verified May 21 2026 production: FastApi provider (Vblink, Ultra Panda) rejects
    # usernames with underscore — returns code 7 "Account format error". Use no-underscore format.
    FASTAPI_NO_UNDERSCORE_SLUGS = %w[vblink ultra_panda].freeze

    USERNAME_BLACKLIST = %w[
      test hi hello hey yo sup ok yes no yeah nah lol lmao sure
      thanks thank please help what how why when where who
      admin root user guest player account login password
    ].freeze

    def valid_username?(username)
      return false if username.blank?
      return false if USERNAME_BLACKLIST.include?(username.to_s.downcase.strip)
      return false if username.to_s.strip.length < 3

      true
    end

    # Bug fix May 19 2026: format diverges by cluster.
    #   Cluster 1 (game_vault, juwa, milky_way, fire_kirin, panda_master, orion_stars):
    #     "mausam397_jw" — underscore separator allowed, easy to extract password from.
    #   Cluster 2 (mafia, game_room, cash_machine, mr_all_in_one):
    #     "mausam397gr"  — NO underscore, panel rejects it (letters+numbers only).
    # password_from_username has matching logic to extract the password back out.
    def generate_auto_username(game_slug = nil)
      suffix = GAME_SUFFIX_MAP[game_slug.to_s] || game_slug.to_s.gsub('_', '')[0..1]
      base = (contact&.name.to_s.downcase.gsub(/[^a-z]/, '')[0..6])
      base = "player" if base.blank? || base.length < 3
      number = SecureRandom.random_number(900) + 100

      if CLUSTER_2_SLUGS.include?(game_slug.to_s) || FASTAPI_NO_UNDERSCORE_SLUGS.include?(game_slug.to_s)
        "#{base}#{number}#{suffix}"
      else
        "#{base}#{number}_#{suffix}"
      end
    end

    # Extracts the password (base + number) from an auto-generated username.
    # Mirrors generate_auto_username's two formats:
    #   Cluster 1 etc:  "mausam963_jw" -> "mausam963" (split on underscore)
    #   Cluster 2:      "mausam963gr"  -> "mausam963" (strip trailing 2-3 alpha chars)
    # game_slug is optional but REQUIRED for correct Cluster 2 extraction; without
    # it we fall back to the legacy underscore-split which is correct for everything
    # except Cluster 2 (where the username has no underscore at all).
    def password_from_username(username, game_slug = nil)
      if game_slug.present? && (CLUSTER_2_SLUGS.include?(game_slug.to_s) || FASTAPI_NO_UNDERSCORE_SLUGS.include?(game_slug.to_s))
        username.to_s.sub(/[a-z]{2,3}\z/i, '')
      else
        username.to_s.split('_').first || username.to_s
      end
    end

    # Generate a compliant new password for a password reset on the given game.
    # Format mirrors the create-time pattern (firstname + 3-digit number) but adapts
    # to per-game rules:
    #   - Cluster 2 panels (Mafia/Gameroom/Cashmachine/MrAllInOne): require upper+lower+special, max 12 chars
    #     -> "Mausa!412" pattern (capitalize first letter, insert "!", ~9 chars)
    #   - Everything else: alphanumeric 6+ chars
    #     -> "mausam412" pattern (same as create)
    def generate_reset_password(game_slug)
      base = contact&.name.to_s.downcase.gsub(/[^a-z]/, '')[0..5]
      base = 'player' if base.blank? || base.length < 3
      num  = SecureRandom.random_number(900) + 100

      if CLUSTER_2_RESET_STRONG_PW.include?(game_slug.to_s)
        # Capitalize first char, trim to 5 chars to leave room for "!" + 3 digits = 9 total (under 12 limit)
        short_base = base[0..4]
        "#{short_base.capitalize}!#{num}"
      else
        # Alphanumeric format, identical to create-time password
        "#{base}#{num}"
      end
    end

    # Picks the game slug in priority order:
    #   1. intent[:game_slug] from latest message detection
    #   2. contact.custom_attributes['preferred_platform']
    #   3. last game mentioned in recent conversation history
    #   4. 'game_vault' (absolute last resort)
    def chosen_game_slug(intent)
      explicit = intent.is_a?(Hash) ? intent[:game_slug] : nil
      return explicit if explicit.present?

      preferred = (contact&.custom_attributes || {})['preferred_platform'].to_s.downcase.strip
      mapped = PREFERRED_PLATFORM_TO_SLUG[preferred]
      return mapped if mapped.present?

      history_slug = last_game_slug_from_history
      return history_slug if history_slug.present?

      'game_vault'
    end

    def last_game_slug_from_history
      return nil unless messages.is_a?(Array)

      customer_texts = messages.select do |m|
        if m.is_a?(Hash)
          (m[:role] || m['role']).to_s == 'user'
        else
          m.respond_to?(:incoming?) && m.incoming?
        end
      end

      customer_texts.reverse_each do |m|
        text = if m.is_a?(Hash)
                 (m[:content] || m['content']).to_s
               else
                 m.content.to_s
               end
        slug = Games::IntentDetector.detect_game(text)
        return slug if slug.present?
      end

      nil
    end

    def pick_agent_game(game_slug)
      return nil if game_slug.blank?

      account.agent_games.joins(:game).where(games: { slug: game_slug }, status: 'active').first
    end

    def agent_game_for_intent(intent)
      slug = chosen_game_slug(intent)
      ag = pick_agent_game(slug)
      return ag if ag

      detected_slug = intent.is_a?(Hash) ? intent[:game_slug] : nil
      if detected_slug.present?
        Rails.logger.info("[Orchestrator] detected game unavailable slug=#{detected_slug} account=#{account.id}")
        return { reply: unavailable_game_reply(detected_slug), labels: ['game-unavailable'] }
      end

      nil
    end

    def active_game_names
      account.agent_games.joins(:game).where(status: 'active').map { |ag| ag.game.name }
    end

    def active_games_list_text
      names = active_game_names
      names.present? ? names.join(', ') : 'no games'
    end

    def unavailable_game_reply(detected_slug)
      list = active_games_list_text
      game = Game.find_by(slug: detected_slug)

      if game
        "we don't have #{game.name} set up right now. we got #{list} — which one you want?"
      else
        "i don't recognize that game. we got #{list} — which one you want?"
      end
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

    def recent_customer_text
      # Returns concatenated content of the last 3 customer messages
      # to handle split intent like "Load me 20$ on" + "Game vault"
      return nil unless messages.is_a?(Array)

      customer_messages = messages.select do |m|
        if m.is_a?(Hash)
          role = m[:role] || m['role']
          role.to_s == 'user'
        else
          m.respond_to?(:incoming?) && m.incoming?
        end
      end

      return nil if customer_messages.empty?

      recent = customer_messages.last(3)
      texts = recent.map do |m|
        if m.is_a?(Hash)
          (m[:content] || m['content']).to_s
        else
          m.content.to_s
        end
      end

      texts.reject(&:blank?).join(' ').strip.presence
    end

    def stored_game_username(game_slug)
      key = "game_username_#{game_slug}"
      (contact.custom_attributes || {})[key]
    end

    def verified_stored_game_username(ag)
      existing_username = stored_game_username(ag.game.slug)
      return nil if existing_username.blank?

      begin
        client = Games::ClientRegistry.client_for(ag)
        check = client.get_user_id(account_name: existing_username)
        unless check.is_a?(Hash) && check.dig('data', 'user_id').present?
          Rails.logger.warn("[Orchestrator] stored username #{existing_username} not found on #{ag.game.slug} — clearing stale creds")
          clear_game_credentials(ag.game.slug)
          return nil
        end
      rescue StandardError => e
        Rails.logger.warn("[Orchestrator] verify stored creds failed: #{e.message} — proceeding with stored")
      end

      existing_username
    end

    def add_player_safe(executor, game_username:, password:, metadata: {})
      Timeout.timeout(45) do
        executor.add_player(game_username: game_username, password: password, metadata: metadata)
      end
    rescue Timeout::Error
      Rails.logger.error("[Orchestrator] add_player timed out after 45s for #{game_username}")
      { ok: false, error: 'Account creation timed out', code: 'timeout' }
    end

    def terminal_add_failure?(add_result)
      %w[silent_fail timeout].include?(add_result[:code].to_s)
    end

    def attempt_auto_add_player(executor, game_slug, metadata: {})
      username = generate_auto_username(game_slug)
      password = password_from_username(username, game_slug)
      result = add_player_safe(executor, game_username: username, password: password, metadata: metadata)
      return [result, username, password] if result[:ok] || terminal_add_failure?(result)

      username = generate_auto_username(game_slug)
      password = password_from_username(username, game_slug)
      result = add_player_safe(executor, game_username: username, password: password, metadata: metadata)
      [result, username, password]
    end

    def add_player_failure_response(ag, add_result)
      case add_result[:code].to_s
      when 'silent_fail'
        Rails.logger.error("[Orchestrator] SILENT FAIL on #{ag.game.slug} — not storing credentials")
        safe_telegram do
          Games::TelegramNotifier.human_escalation(
            account: account, contact: contact,
            reason: "Silent fail creating account on #{ag.game.name}: #{add_result[:error]}",
            conversation: conversation
          )
        end
        {
          reply: 'hit a snag setting up your account — flagged a teammate',
          labels: ['silent-fail', 'needs-human']
        }
      when 'timeout'
        Rails.logger.error("[Orchestrator] add_player timed out on #{ag.game.slug}")
        safe_telegram do
          Games::TelegramNotifier.human_escalation(
            account: account, contact: contact,
            reason: "Account creation timed out on #{ag.game.name}",
            conversation: conversation
          )
        end
        {
          reply: "hit a snag setting up your #{ag.game.name} account — flagged a teammate, they'll get you sorted in a couple minutes.",
          labels: ['account-creation-failed', 'needs-human']
        }
      end
    end

    def stored_game_password(game_slug)
      key = "game_password_#{game_slug}"
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

    def find_matching_confirmed_payment(requested_amount)
      logs = (contact.custom_attributes || {})['patra_finance_logs']
      return nil unless logs.is_a?(Array)

      logs.reverse.each do |log|
        next unless log.is_a?(Hash)

        # Status must be confirmed/completed/verified (case-insensitive)
        status = log['status'].to_s.downcase
        # Accept "Email Verified", "Loaded"-eligible, and legacy confirmed/completed/verified
        acceptable = %w[confirmed completed verified].include?(status) ||
                     status.include?('verified') ||
                     status == 'email verified'
        next unless acceptable

        # CRITICAL: Reject flagged duplicates and anything with a flag_reason
        next if log['flag_reason'].to_s.strip.length > 0
        if Payments::StatusNormalizer.needs_email_confirmation?(log['raw_status'])
          next unless log['email_confirmed'] == true
        end

        amount = parse_amount(log['amount'])
        next if amount.nil? || amount <= 0

        time_str = log['recorded_at'] || log['image_received_at'] || log['transaction_time']
        recorded = parse_time(time_str)
        # TIGHTER WINDOW: 30 minutes, not 6 hours
        next if recorded && recorded < 30.minutes.ago

        log_id = log['id'] || log['transaction_id'] || "#{log['amount']}_#{log['recorded_at']}"
        next if payment_already_loaded?(log_id, amount, recorded)

        if (amount - requested_amount).abs < 0.01
          Rails.logger.info("[Orchestrator] matched payment id=#{log_id} amount=#{amount} for requested=#{requested_amount}")
          return { id: log_id, amount: amount, method: log['platform'], recorded_at: recorded }
        end
      end

      Rails.logger.info("[Orchestrator] no matching confirmed payment for requested=#{requested_amount}, log_count=#{logs.size}")
      nil
    end

    def find_unloaded_confirmed_payment
      logs = (contact.custom_attributes || {})['patra_finance_logs']
      return nil unless logs.is_a?(Array)

      logs.reverse.each do |log|
        next unless log.is_a?(Hash)

        status = log['status'].to_s.downcase
        # Accept "Email Verified", "Loaded"-eligible, and legacy confirmed/completed/verified
        acceptable = %w[confirmed completed verified].include?(status) ||
                     status.include?('verified') ||
                     status == 'email verified'
        next unless acceptable

        # Reject flagged duplicates
        next if log['flag_reason'].to_s.strip.length > 0
        if Payments::StatusNormalizer.needs_email_confirmation?(log['raw_status'])
          next unless log['email_confirmed'] == true
        end

        amount = parse_amount(log['amount'])
        next if amount.nil? || amount <= 0

        time_str = log['recorded_at'] || log['image_received_at'] || log['transaction_time']
        recorded = parse_time(time_str)
        # Customers send payment screenshots up to ~48h after paying
        next if recorded && recorded < 48.hours.ago

        log_id = log['id'].presence || log['transaction_id'].presence || log['image_url'].presence || "#{log['amount']}_#{log['recorded_at']}"
        next if payment_already_loaded?(log_id, amount, recorded)

        Rails.logger.info("[Orchestrator] found unloaded payment id=#{log_id} amount=#{amount}")
        return { id: log_id, amount: amount, method: log['platform'], recorded_at: recorded }
      end
      nil
    end

    def payment_already_loaded?(payment_id, amount, recorded_time)
      return true if GameAction
        .where(account_id: account.id, contact_id: contact.id, action_type: 'load', status: 'success')
        .where("metadata::text LIKE ?", "%#{payment_id}%")
        .exists?
      # Fallback: any successful load for this amount in the same window
      if recorded_time
        return GameAction
          .where(account_id: account.id, contact_id: contact.id, action_type: 'load', status: 'success', amount: amount)
          .where('created_at >= ?', recorded_time)
          .exists?
      end
      false
    end

    def mark_payment_loaded(payment_id, game_slug: nil, game_username: nil)
      logs = (contact.custom_attributes || {})['patra_finance_logs']
      if logs.is_a?(Array)
        modified = false
        logs.each do |entry|
          next unless entry.is_a?(Hash)

          log_id = entry['id'].presence || entry['transaction_id'].presence || entry['image_url'].presence || "#{entry['amount']}_#{entry['recorded_at']}"
          matches = log_id.to_s == payment_id.to_s ||
                    entry['transaction_id'].to_s == payment_id.to_s
          next unless matches

          entry['status'] = 'Loaded'
          entry['game_load_success'] = true
          entry['loaded_at'] = Time.current.iso8601
          entry['loaded_game_slug'] = game_slug if game_slug.present?
          entry['loaded_game_username'] = game_username if game_username.present?
          modified = true
          break
        end

        if modified
          attrs = (contact.custom_attributes || {}).stringify_keys
          attrs['patra_finance_logs'] = logs
          contact.custom_attributes = attrs
          contact.save!(touch: false)
        end
      end

      Rails.logger.info("[Orchestrator] payment #{payment_id} marked loaded game=#{game_slug} user=#{game_username}")
    end

    def parse_amount(val)
      return nil if val.nil?
      val.to_s.gsub(/[^\d.]/, '').to_f.then { |f| f > 0 ? f : nil }
    end

    def parse_time(str)
      return nil if str.blank?
      Time.parse(str.to_s)
    rescue ArgumentError
      nil
    end

    def active_payment_handle_for_account
      if defined?(PaymentHandle)
        handle = PaymentHandle.where(account_id: account.id, status: 'active').order(:id).first
        return handle.handle.to_s if handle
      end
      'the payment handle in our last message'
    end

    # Returns array of unique active platforms for this account, e.g. ["cashapp", "paypal", "venmo", "chime"]
    def active_payment_platforms
      return [] unless defined?(PaymentHandle)
      PaymentHandle.where(account_id: account.id, status: 'active')
                   .pluck(:platform).uniq
    rescue StandardError => e
      Rails.logger.error("[Orchestrator] active_payment_platforms failed: #{e.class}: #{e.message}")
      []
    end

    # Returns the top-priority active display_name (e.g. "$sofiamann8") for the given platform.
    # Returns nil if no active handle exists for that platform.
    def top_handle_for_platform(platform)
      return nil unless defined?(PaymentHandle)
      ph = PaymentHandle.where(account_id: account.id, platform: platform.to_s, status: 'active')
                        .order(:priority).first
      return nil unless ph
      ph.respond_to?(:display_handle) ? ph.display_handle : (ph.try(:display_name).presence || ph.try(:handle))
    rescue StandardError => e
      Rails.logger.error("[Orchestrator] top_handle_for_platform(#{platform}) failed: #{e.class}: #{e.message}")
      nil
    end

    # Returns the "which method?" question, dynamically built from active platforms.
    # Falls back to the single-handle string if no platforms are configured.
    def payment_methods_question
      platforms = active_payment_platforms
      return "send your deposit to #{active_payment_handle_for_account} and drop the screenshot here" if platforms.empty?

      pretty = platforms.map do |p|
        case p.to_s.downcase
        when 'cashapp' then 'cashapp'
        when 'chime'   then 'chime'
        when 'venmo'   then 'venmo'
        when 'paypal'  then 'paypal'
        when 'zelle'   then 'zelle'
        else p.to_s
        end
      end

      list = if pretty.size == 1
               pretty.first
             elsif pretty.size == 2
               pretty.join(' or ')
             else
               "#{pretty[0..-2].join(', ')}, or #{pretty.last}"
             end

      "we got #{list} 🙌 which one you wanna use?"
    end

    # Handler for when the customer picks a payment method ("paypal", "i'll use cashapp", etc.)
    # Looks up the top-priority active handle for that platform and replies with it.
    def handle_payment_method_chosen(intent)
      platform = intent[:platform].to_s.downcase.strip
      handle_text = top_handle_for_platform(platform)

      unless handle_text
        Rails.logger.warn("[Orchestrator] payment_method_chosen no active handle for platform=#{platform}")
        return {
          reply: payment_methods_question,
          labels: ['payment-method-unavailable']
        }
      end

      Rails.logger.info("[Orchestrator] payment_method_chosen platform=#{platform} handle=#{handle_text}")
      store_expected_payment_handle!(platform: platform, handle: handle_text)
      {
        reply: "easy! send to #{handle_text} on #{platform} and drop the screenshot here 📸",
        labels: ['payment-method-chosen', "payment-#{platform}"]
      }
    end

    # Customer asked to reset their password on a game.
    # Required intent fields: :game_slug (string slug like 'mafia')
    # Optional intent fields: :game_username (string), :new_password (string, customer-supplied)
    # Falls back to stored username and auto-generated password if not provided.
    def handle_reset_password_intent(intent)
      game_slug = intent[:game_slug]
      if game_slug.present?
        ag = pick_agent_game(game_slug)
        unless ag
          return { reply: unavailable_game_reply(game_slug), labels: ['game-unavailable'] }
        end
      else
        ag = account.agent_games.joins(:game).where(status: 'active').first
        unless ag
          return {
            reply: "which game do you want me to reset? (juwa, milky way, mafia, etc.)",
            labels: ['reset-needs-game']
          }
        end
      end

      # Resolve the username: explicit > stored. Don't auto-create here — reset on a
      # nonexistent account is wrong, the customer should request account creation instead.
      username = intent[:game_username].presence || stored_game_username(ag.game.slug)

      if username.blank?
        return {
          reply: "what's your #{ag.game.name} username? need it to reset your password.",
          labels: ['reset-needs-username']
        }
      end

      # Generate or accept the new password. Customer-supplied passwords are not honored yet
      # (panels have strict rules and customers tend to pick noncompliant ones). Always auto-generate.
      new_password = generate_reset_password(ag.game.slug)

      executor = Games::ActionExecutor.new(agent_game: ag, contact: contact, conversation: conversation)
      result = executor.reset_player_password(
        game_username: username,
        new_password: new_password,
        metadata: { source: 'bella_auto_reset', conversation_id: conversation&.id }
      )

      if result[:ok]
        store_game_password(ag.game.slug, new_password)
        {
          reply: "your new #{ag.game.name} password is #{new_password} — save this! 🎰",
          labels: ['password-reset']
        }
      else
        safe_telegram do
          Games::TelegramNotifier.human_escalation(
            account: account, contact: contact,
            reason: "Password reset failed on #{ag.game.name} for #{username}: #{result[:error]}",
            conversation: conversation
          )
        end
        {
          reply: "hit a snag resetting your #{ag.game.name} password — flagged a teammate, they'll handle it shortly.",
          labels: ['reset-failed', 'needs-human']
        }
      end
    end

    def handle_payment_sent_confirmation(intent)
      contact = conversation.contact

      begin
        if defined?(Payments::EmailConfirmationService)
          Payments::EmailConfirmationService.new(contact: contact).check_all
          Rails.logger.info("[Orchestrator] IMAP check triggered for #{contact.name}")
        end
      rescue StandardError => e
        Rails.logger.error("[Orchestrator] IMAP trigger failed: #{e.message}")
      end

      begin
        attrs = conversation.additional_attributes || {}
        attrs['awaiting_imap_confirmation'] = true
        conversation.update!(additional_attributes: attrs)
      rescue StandardError => e
        Rails.logger.error("[Orchestrator] Flag set failed: #{e.message}")
      end

      safe_telegram do
        Games::TelegramNotifier.human_escalation(
          account: account, contact: contact,
          reason: "Payment sent confirmation from #{contact.name} — IMAP check triggered",
          conversation: conversation
        )
      end

      { reply: 'checking now — will load once confirmed!', labels: ['payment-pending'] }
    end

    def handle_status_check(intent)
      contact = conversation.contact
      game_slug = chosen_game_slug(intent) || contact.custom_attributes&.dig('preferred_platform')
      labels = ['status-check']

      begin
        last_action = GameAction.where(contact_id: contact.id)
        if game_slug.present?
          last_action = last_action.joins(agent_game: :game).where(games: { slug: game_slug })
        end
        last_action = last_action.order(created_at: :desc).first

        if last_action
          action_slug = last_action.agent_game&.game&.slug || game_slug
          case last_action.status
          when 'success'
            amt = last_action.amount ? "$#{last_action.amount.to_i}" : ''
            reply = "your last #{last_action.action_type} #{amt} on #{action_slug} went through ✅"
          when 'pending'
            reply = 'still processing — will update you soon!'
          when 'failed'
            reply = "there was an issue with your last #{last_action.action_type} — let me look into it"
            safe_telegram do
              Games::TelegramNotifier.human_escalation(
                account: account, contact: contact,
                reason: "Status check — last action FAILED for #{contact.name} on #{action_slug}",
                conversation: conversation
              )
            end
            labels << 'cashier-action-needed'
          else
            reply = 'checking on that — one moment!'
            safe_telegram do
              Games::TelegramNotifier.human_escalation(
                account: account, contact: contact,
                reason: "Status check from #{contact.name} — status: #{last_action.status}",
                conversation: conversation
              )
            end
          end
        else
          reply = "can you remind me which game? I'll check for you"
        end
      rescue StandardError => e
        Rails.logger.error("[Orchestrator] Status check failed: #{e.message}")
        reply = 'checking on that — one moment!'
        safe_telegram do
          Games::TelegramNotifier.human_escalation(
            account: account, contact: contact,
            reason: "Status check from #{contact.name} (lookup failed: #{e.message})",
            conversation: conversation
          )
        end
      end

      { reply: reply, labels: labels.uniq }
    end

    def handle_complaint_angry(intent = nil)
      contact = conversation.contact

      # Pull RAG examples for complaint-style replies
      cashier_reply = nil
      begin
        results = BellaRag::IntentRetriever.retrieve(
          text: (latest_customer_text || recent_customer_text).to_s,
          account_id: conversation.account_id,
          top_k: 3,
          threshold: 0.30
        )
        if results.present?
          # Pick the shortest cashier reply as the calming response
          cashier_reply = results
            .map { |r| r[:cashier_text] || r['cashier_text'] }
            .compact
            .reject { |t| t.to_s.strip.length < 3 }
            .min_by { |t| t.length }
        end
      rescue StandardError => e
        Rails.logger.error("[Orchestrator] RAG complaint lookup failed: #{e.message}")
      end

      # Reply like a real cashier first — calming, human
      reply_text = cashier_reply || "just a min, looking into it"

      # THEN silently escalate to Telegram — customer never knows
      begin
        Games::TelegramNotifier.human_escalation(
          account: account,
          contact: contact,
          reason: "complaint_angry — Customer upset: #{(latest_customer_text || '').truncate(100)}",
          conversation: conversation
        )
      rescue StandardError => e
        Rails.logger.error("[Orchestrator] Complaint Telegram escalation failed: #{e.message}")
      end

      {
        reply: reply_text,
        labels: %w[needs-human cashier-action-needed]
      }
    end

    def handle_tech_issue(intent = nil)
      contact = conversation.contact
      game_slug = chosen_game_slug(intent || { intent: :tech_issue })

      # Try to find credentials for this contact + game
      credentials_sent = false
      if game_slug
        begin
          username = find_game_username_for_slug(contact, game_slug)
          if username
            # Find the game link from game_rules
            game = Game.find_by(slug: game_slug)
            rules = game ? GameRule.find_by(account_id: conversation.account_id, game_id: game.id) : nil
            download_url = rules&.game_download_url
            web_url = rules&.game_web_url

            # Build credentials reply
            parts = []
            parts << "your #{game_slug} login: #{username}"
            parts << "download: #{download_url}" if download_url.present?
            parts << "play here: #{web_url}" if web_url.present? && download_url.blank?

            if parts.any?
              credentials_sent = true
              reply_text = parts.join("\n")
            end
          end
        rescue StandardError => e
          Rails.logger.error("[Orchestrator] Tech issue credential lookup failed: #{e.message}")
        end
      end

      # If we couldn't send credentials, use RAG example or fallback
      unless credentials_sent
        begin
          results = BellaRag::IntentRetriever.retrieve(
            text: (latest_customer_text || recent_customer_text).to_s,
            account_id: conversation.account_id,
            top_k: 3,
            threshold: 0.30
          )
          if results.present?
            reply_text = results
              .map { |r| r[:cashier_text] || r['cashier_text'] }
              .compact
              .reject { |t| t.to_s.strip.length < 3 }
              .first
          end
        rescue StandardError => e
          Rails.logger.error("[Orchestrator] RAG tech issue lookup failed: #{e.message}")
        end

        reply_text ||= "let me check on that for you — one sec"
      end

      # Escalate to Telegram only if we couldn't auto-resolve
      unless credentials_sent
        begin
          Games::TelegramNotifier.human_escalation(
            account: account,
            contact: contact,
            reason: "tech_issue — Tech issue: #{(latest_customer_text || '').truncate(100)}. Game: #{game_slug || 'unknown'}",
            conversation: conversation
          )
        rescue StandardError => e
          Rails.logger.error("[Orchestrator] Tech issue Telegram escalation failed: #{e.message}")
        end
      end

      {
        reply: reply_text,
        labels: credentials_sent ? ['status-check'] : %w[needs-human cashier-action-needed]
      }
    end

    def handle_balance_check(intent)
      contact = conversation.contact
      game_slug = chosen_game_slug(intent) || contact.custom_attributes&.dig('preferred_platform')

      unless game_slug
        return { reply: 'which game do you want me to check?', labels: ['balance-check-requested'] }
      end

      begin
        username = find_game_username_for_slug(contact, game_slug)
        unless username
          return {
            reply: "I don't have your #{game_slug} account on file — which username?",
            labels: ['balance-check-requested']
          }
        end

        result = execute_game_api(
          game_slug: game_slug,
          action: 'agent_balance',
          username: username
        )

        if result[:success] && result[:balance]
          balance = result[:balance]
          reply = "your #{game_slug} balance is $#{balance}"

          begin
            game = Game.find_by(slug: game_slug)
            rules = game ? GameRule.find_by(account_id: account.id, game_id: game.id) : nil
            if rules && rules.cashout_rules_text.present? && balance.to_f >= (rules.cashout_min_amount || 10)
              reply += "\ncashout rules: #{rules.cashout_rules_text}"
            end
          rescue StandardError => e
            Rails.logger.error("[Orchestrator] Cashout rules lookup failed: #{e.message}")
          end

          { reply: reply, labels: ['balance-check-requested'] }
        else
          safe_telegram do
            Games::TelegramNotifier.human_escalation(
              account: account, contact: contact,
              reason: "Balance check failed for #{contact.name} on #{game_slug}: #{result[:error]}",
              conversation: conversation
            )
          end
          {
            reply: "couldn't pull your balance right now — let me check manually",
            labels: %w[cashier-action-needed balance-check-requested]
          }
        end
      rescue StandardError => e
        Rails.logger.error("[Orchestrator] Balance check failed: #{e.message}")
        safe_telegram do
          Games::TelegramNotifier.human_escalation(
            account: account, contact: contact,
            reason: "Balance check error for #{contact.name}: #{e.message}",
            conversation: conversation
          )
        end
        {
          reply: 'let me pull that up — one sec',
          labels: %w[cashier-action-needed balance-check-requested]
        }
      end
    end

    def handle_transfer_between_games(intent)
      safe_telegram do
        Games::TelegramNotifier.human_escalation(
          account: account,
          contact: contact,
          reason: 'Transfer between games requested — needs cashier'
        )
      end
      { reply: "transfers between games need manual processing — getting a cashier to help you now!", labels: ['cashier-action-needed', 'needs-human'] }
    end

    def handle_whats_hitting(intent)
      games_text = active_games_list_text
      reply = games_text.present? ? "right now we have: #{games_text} — which one do you want loaded?" : "let me check which games are available and get back to you!"
      { reply: reply, labels: [] }
    end

    def handle_referral(intent)
      safe_telegram do
        Games::TelegramNotifier.human_escalation(
          account: account,
          contact: contact,
          reason: 'Customer made a referral — verify and apply referral bonus if applicable'
        )
      end
      { reply: "thanks so much for the referral! i've noted it and someone will follow up with you shortly", labels: ['referral-pending'] }
    end

    def handle_redeem_partial_replay(intent)
      safe_telegram do
        Games::TelegramNotifier.human_escalation(
          account: account,
          contact: contact,
          reason: 'Partial cashout + replay requested — needs manual cashier calculation'
        )
      end
      { reply: "got it — partial cashout with a reload needs manual processing, getting a cashier on it now!", labels: ['cashier-action-needed', 'needs-human'] }
    end

    def handle_new_account_reissue(intent)
      safe_telegram do
        Games::TelegramNotifier.human_escalation(
          account: account,
          contact: contact,
          reason: 'Account reissue requested — existing account broken, needs replacement'
        )
      end
      { reply: "no worries! let me get someone to sort out your account replacement right away", labels: ['needs-human', 'account-reissue'] }
    end

    def handle_replay_from_balance(intent)
      safe_telegram do
        Games::TelegramNotifier.human_escalation(
          account: account,
          contact: contact,
          reason: 'Replay from existing balance requested — needs cashier to verify and load'
        )
      end
      { reply: "got it — loading from your existing balance needs a quick check, cashier will handle it now!", labels: ['cashier-action-needed', 'needs-human'] }
    end

    # Bug 7 fix: payment_request_reply now mirrors handle_payment_method_chosen
    # by including the platform ("send $5 to X on cashapp"). If platform is
    # blank or handle_text already contains the platform name (legacy single-
    # handle format like "cashapp sofia mann"), we skip the suffix to avoid
    # duplicates ("send $5 to cashapp sofia mann on cashapp" would be ugly).
    def payment_request_reply(amount, handle_text, platform, game_name)
      handle_str = handle_text.to_s.strip
      platform_str = platform.to_s.strip.downcase
      already_has_platform = platform_str.present? && handle_str.downcase.include?(platform_str)
      suffix = (platform_str.present? && !already_has_platform) ? " on #{platform_str}" : ''
      amount_f = amount.to_f
      amount_str = amount_f > 0 ? "$#{format('%g', amount_f)} " : ''
      "got it! send #{amount_str}to #{handle_str}#{suffix}, then drop the screenshot here 📸 — i'll load it on #{game_name} as soon as it confirms."
    end

    def honest_failure_reply(result, amount, game_name)
      case result[:code]
      when 8
        "hmm — that username doesn't exist on #{game_name} yet. want me to create it? just confirm and i'll set you up."
      when 6
        "hit a temporary issue on our end — flagged a teammate, they'll load your $#{amount} in a couple minutes. you'll get a notification when it's done."
      when 5
        "couldn't reach #{game_name} just now — flagged a teammate to look at it, they'll have your $#{amount} loaded in a few minutes."
      else
        "ran into a snag loading your $#{amount} — flagged a teammate to handle it manually. they'll have you loaded in a couple minutes."
      end
    end

    def store_game_password(slug, password)
      key = "game_password_#{slug}"
      attrs = (contact.custom_attributes || {}).merge(key => password)
      contact.update(custom_attributes: attrs)
    end

    def clear_game_credentials(slug)
      attrs = (contact.custom_attributes || {}).dup
      attrs.delete("game_username_#{slug}")
      attrs.delete("game_password_#{slug}")
      contact.update(custom_attributes: attrs)
    end

    def safe_telegram
      yield
    rescue StandardError => e
      Rails.logger.error("[Orchestrator] Telegram call failed: #{e.class}: #{e.message}")
    end

    def store_expected_payment_handle!(platform:, handle:)
      return if conversation.blank? || platform.blank? || handle.blank?

      begin
        attrs = (conversation.additional_attributes || {}).stringify_keys
        attrs['expected_platform'] = platform.to_s.downcase
        attrs['expected_handle'] = handle.to_s
        attrs['expected_handle_at'] = Time.current.iso8601
        conversation.additional_attributes = attrs
        conversation.save!
        Rails.logger.info("[Orchestrator] stored expected payment handle platform=#{platform} handle=#{handle}")
      rescue StandardError => e
        Rails.logger.warn("[Orchestrator] store_expected_payment_handle! failed: #{e.message}")
      end
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

    # Removes 'cashout-requested' label if present. Used at the START of
    # every new cashout intent handling so a prior cashout's label can't
    # pollute the next turn's logic. Never raises — pure cleanup.
    def clear_stale_cashout_label_safely
      return unless conversation&.respond_to?(:label_list)

      current = Array(conversation.label_list)
      return unless current.include?('cashout-requested')

      conversation.label_list.remove('cashout-requested')
      conversation.save!
    rescue StandardError => e
      Rails.logger.warn("[Orchestrator][CashoutGuard] label cleanup failed: #{e.class}: #{e.message}")
    end

    def find_game_username_for_slug(contact, game_slug)
      ag = pick_agent_game(game_slug)
      return nil unless ag

      verified_stored_game_username(ag) || stored_game_username(game_slug)
    end

    def game_actions_for_slug(contact_id, game_slug)
      GameAction.joins(agent_game: :game)
                .where(contact_id: contact_id, games: { slug: game_slug })
    end

    def execute_game_api(game_slug:, action:, username:, amount: nil)
      ag = pick_agent_game(game_slug)
      return { success: false, error: 'game unavailable' } unless ag

      executor = Games::ActionExecutor.new(agent_game: ag, contact: contact, conversation: conversation)

      case action.to_s
      when 'recharge', 'load'
        result = executor.load_player(
          game_username: username,
          amount: amount,
          metadata: { source: 'bella_orchestrator' }
        )
        { success: result[:ok], error: result[:error], balance: nil }
      when 'agent_balance', 'balance'
        balance = executor.check_player_balance(game_username: username)
        if balance.present?
          { success: true, balance: balance }
        else
          { success: false, error: 'balance lookup failed' }
        end
      else
        { success: false, error: "unknown action #{action}" }
      end
    rescue StandardError => e
      Rails.logger.error("[Orchestrator] execute_game_api failed: #{e.message}")
      { success: false, error: e.message }
    end
  end
end
