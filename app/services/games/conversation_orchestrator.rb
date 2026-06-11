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
      'redeem_partial_replay'     => :redeem_partial_replay,
      'replay_from_balance'       => :replay_from_balance,
      'new_account_new_player'    => :request_account_creation,
      'new_account_other_game'    => :request_account_creation,
      'request_game_link'         => :request_game_link,
      'request_download_link'     => :request_download_link,
      'request_app_link'          => :request_app_link,
      'cashout_rules'             => :cashout_rules,
      'list_platforms'            => :list_platforms,
      'payment_method_question'   => :payment_method_question,
      # TAB A F-RAG: cover all 27 DB real_intent labels. greeting_chitchat
      # routes to :greeting (no orchestrator handler -> handle returns nil ->
      # LLM brain replies). 'unclear' maps to nil ON PURPOSE: the cutover
      # branch treats nil as no-route and falls through to the LLM - never
      # crashes, never mis-routes.
      'greeting_chitchat'         => :greeting,
      'unclear'                   => nil
    }.freeze
    RAG_CUTOVER_CONFIDENCE = 0.40   # min RAG confidence to route when regex returns nil (was 0.60; lowered per 73k brain test)
    # Finding-2 fix: block an identical cashout (same game + amount) within this window —
    # guards against duplicate-message double-pay in redeem-partial + transfer.
    CASHOUT_DEDUP_WINDOW_SECONDS = 120

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

      # R6b - a pending "use that one or make a new one?" answer takes priority.
      pending_choice = (contact.custom_attributes || {})['pending_account_choice']
      if pending_choice.present?
        choice_response = resolve_pending_account_choice(latest_text, pending_choice)
        return choice_response if choice_response
      end

      # MEGA2 P3 - a pending over-max "keep it or drop it?" answer (ask_first
      # mode) takes priority. No usable answer -> falls through, nothing moves.
      pending_overmax = conversation&.additional_attributes&.dig('pending_overmax_choice')
      if pending_overmax.present?
        overmax_response = resolve_pending_overmax_choice(latest_text, pending_overmax)
        return overmax_response if overmax_response
      end

      # Process pending load/cashout confirmations
      pending_load = conversation.additional_attributes&.dig('pending_load_intent')
      pending_cashout = conversation.additional_attributes&.dig('pending_cashout')
      pending_transfer_create = (contact.custom_attributes || {})['pending_transfer_create']
      if pending_load.present? || pending_cashout.present? || pending_transfer_create.present?
        answer = latest_text.to_s.strip.downcase
        if answer.match?(/\b(yes|yeah|yep|yea|y|confirm|go|do it|send it)\b/i)
          if pending_load.present?
            begin
              intent_data = JSON.parse(pending_load).symbolize_keys
              # Clear flags
              attrs = conversation.additional_attributes.dup
              attrs.delete('pending_load_intent')
              attrs['load_confirmed'] = true
              conversation.update_columns(additional_attributes: attrs)
              return handle_load_intent(intent_data)
            rescue StandardError => e
              Rails.logger.error("[Orchestrator] Confirm-load processing failed: #{e.message}")
            ensure
              # Clear confirmed flag after processing
              begin
                attrs = conversation.additional_attributes.dup
                attrs.delete('load_confirmed')
                conversation.update_columns(additional_attributes: attrs)
              rescue StandardError
              end
            end
          end
          if pending_cashout.present?
            begin
              attrs = conversation.additional_attributes.dup
              attrs.delete('pending_cashout')
              attrs['cashout_confirmed'] = true
              conversation.update_columns(additional_attributes: attrs)
              # Re-run cashout with confirmed flag (pending_cashout holds game_slug)
              return handle_cashout_intent({ intent: :cashout, game_slug: pending_cashout })
            rescue StandardError => e
              Rails.logger.error("[Orchestrator] Confirm-cashout processing failed: #{e.message}")
            ensure
              begin
                attrs = conversation.additional_attributes.dup
                attrs.delete('cashout_confirmed')
                conversation.update_columns(additional_attributes: attrs)
              rescue StandardError
              end
            end
          end
          if pending_transfer_create.present?
            return complete_pending_transfer_create(pending_transfer_create)
          end
        elsif answer.match?(/\b(no|nah|nope|cancel|nevermind|n)\b/i)
          # Customer declined — clear pending flags
          begin
            attrs = conversation.additional_attributes.dup
            attrs.delete('pending_load_intent')
            attrs.delete('pending_cashout')
            conversation.update_columns(additional_attributes: attrs)
            clear_pending_transfer_create if pending_transfer_create.present?
          rescue StandardError
          end
          return { reply: 'got it, cancelled', labels: [] }
        end
        # If answer is neither yes nor no, fall through to normal intent detection
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
        if _rag && _rag[:confidence].to_f >= RAG_CUTOVER_CONFIDENCE
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
            reason: escalation_context(
              wants: "#{intent_key} - an owner-only action",
              done: 'nothing executed - this intent is never auto-fulfilled',
              left: 'the requested action itself',
              suggest: 'handle it manually if legit',
              need: "decide on the #{intent_key} request and reply to the player"
            ),
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
      when :request_game_link
        handle_request_game_link(intent)
      when :request_download_link
        handle_request_download_link(intent)
      when :request_app_link
        handle_request_app_link(intent)
      when :cashout_rules
        handle_cashout_rules(intent)
      when :list_platforms
        handle_list_platforms(intent)
      when :payment_method_question
        handle_payment_method_question(intent)
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

      # Check confirm-before-load preference
      begin
        pref = ReplyPreference.for_account(account.id)
        if pref&.confirm_before_load
          # Only confirm if we haven't already confirmed (check conversation flag)
          unless conversation.additional_attributes&.dig('load_confirmed')
            game_slug_display = chosen_game_slug(intent) || 'your game'
            amount_display = intent[:amount].to_f > 0 ? "$#{intent[:amount].to_i}" : 'your deposit'
            attrs = (conversation.additional_attributes || {}).merge('pending_load_intent' => intent.to_json)
            conversation.update_columns(additional_attributes: attrs)
            return {
              reply: "confirm load #{amount_display} on #{game_slug_display}? (yes/no)",
              labels: []
            }
          end
        end
      rescue StandardError => e
        Rails.logger.error("[Orchestrator] Confirm-before-load check failed: #{e.message}")
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

      # R7 - verified deposits above the auto-load threshold need a human first.
      hold = over_threshold_load_hold(payment, ag.game.name)
      return hold if hold

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

      # Feature 4 — duplicate-payment guard: don't double-load the same amount within 10 min.
      if duplicate_payment_check_enabled? && duplicate_recent_load?(requested_amount)
        safe_telegram do
          Games::TelegramNotifier.human_escalation(
            account: account, contact: contact,
            reason: escalation_context(
              wants: "to load $#{fmt_amt(requested_amount)} (looks like a DUPLICATE PAYMENT)",
              done: 'same amount loaded successfully within the last 10 min - this one was HELD, nothing loaded',
              left: "the held $#{fmt_amt(requested_amount)} load",
              suggest: 'check the ledger for two real payments vs a double-send',
              need: 'confirm whether this is a second real payment, then load or decline'
            ),
            conversation: conversation
          )
        end
        return { reply: "want to make sure i don't double-load you — having a teammate confirm this one real quick.", labels: %w[duplicate-payment-hold needs-human] }
      end

      # Try to load. If username doesn't exist on Game Vault, auto-create it.
      executor = Games::ActionExecutor.new(agent_game: ag, contact: contact, conversation: conversation)

      # G2 (June 10) - a configured bonus auto-attaches to the qualifying
      # deposit: ONE load of amount + bonus, bonus flagged in metadata (TABA-1
      # single record). The deterministic order_id is unchanged - F12 still
      # collapses duplicates of the same payment.
      auto_bonus = compute_auto_bonus(requested_amount, ag.game.slug)
      load_total = requested_amount + auto_bonus
      bonus_note = auto_bonus.positive? ? " + $#{fmt_amt(auto_bonus)} bonus" : ''
      bonus_meta = auto_bonus.positive? ? { deposit_bonus: true, deposit_amount: requested_amount, bonus_amount: auto_bonus, bonus_source: 'auto_percent' } : {}
      log_generosity_decision(kind: 'bonus', decision: 'given', amount: auto_bonus, source: 'auto_percent') if auto_bonus.positive?

      # F12: deterministic order_id - concurrent duplicates of the SAME payment
      # collapse on the unique index instead of double-loading.
      load_order_id = deterministic_payment_order_id(payment[:id])
      return already_loaded_response(requested_amount) if load_order_id.nil?

      result = begin
        executor.load_player(
          game_username: username,
          amount: load_total,
          payment_method: payment[:method],
          metadata: { source: 'bella_auto', payment_id: payment[:id], message: recent_customer_text.to_s[0..200] }.merge(bonus_meta),
          order_id: load_order_id
        )
      rescue Games::ActionExecutor::IdempotencyError, ActiveRecord::RecordNotUnique
        return already_loaded_response(requested_amount)
      end

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
              reason: escalation_context(
                wants: "$#{fmt_amt(requested_amount)} loaded on #{ag.game.name} (new account needed)",
                done: "payment verified; account creation for '#{username}' FAILED (#{add_result[:error]})",
                left: 'no account, payment not loaded',
                suggest: 'create the account on the panel by hand, then load',
                need: "create #{username} and load $#{fmt_amt(requested_amount)}, then confirm in chat"
              ),
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

        # Retry the load now that user exists. Fresh deterministic id: the
        # failed first attempt freed the base via its attempt suffix.
        retry_order_id = deterministic_payment_order_id(payment[:id])
        return already_loaded_response(requested_amount) if retry_order_id.nil?

        result = begin
          executor.load_player(
            game_username: username,
            amount: load_total,
            payment_method: payment[:method],
            metadata: { source: 'bella_auto_after_create', payment_id: payment[:id] }.merge(bonus_meta),
            order_id: retry_order_id
          )
        rescue Games::ActionExecutor::IdempotencyError, ActiveRecord::RecordNotUnique
          return already_loaded_response(requested_amount)
        end

        if result[:ok]
          mark_payment_loaded(payment[:id], game_slug: ag.game.slug, game_username: username)
          # Check if deposit bonus applies (auto-bonus without customer saying "bonus")
          begin
            game_slug = ag.game.slug
            game = Game.find_by(slug: game_slug) if game_slug
            rules = game ? GameRule.find_by(account_id: account.id, game_id: game.id) : nil
            if rules&.deposit_bonus_enabled && rules.deposit_bonus_eligible?(contact)
              bonus = rules.calculate_bonus(requested_amount)
              if bonus > 0
                Rails.logger.info("[Orchestrator] Auto-bonus: #{bonus} on #{game_slug} for #{contact.name}")
                # Bonus is informational — load already happened at base amount
                # Next iteration: load base+bonus together
              end
            end
          rescue StandardError => e
            Rails.logger.error("[Orchestrator] Auto-bonus check failed: #{e.message}")
          end
          # Check if this deposit qualifies contact for VIP auto-promote
          begin
            Games::TierAutoPromoteService.check(contact: contact)
          rescue StandardError => e
            Rails.logger.error("[Orchestrator] Auto-promote check failed: #{e.message}")
          end
          return apply_receipt_preference({
            reply: "created your account! username: #{username}, password: #{generated_password} (save this!) — loaded $#{requested_amount} 🎰",
            labels: ['auto-load', 'new-account-created']
          })
        end
      end

      # First-try result handling
      store_game_username(ag.game.slug, username)

      if result[:ok]
        mark_payment_loaded(payment[:id], game_slug: ag.game.slug, game_username: username)
        # Check if deposit bonus applies (auto-bonus without customer saying "bonus")
        begin
          game_slug = ag.game.slug
          game = Game.find_by(slug: game_slug) if game_slug
          rules = game ? GameRule.find_by(account_id: account.id, game_id: game.id) : nil
          if rules&.deposit_bonus_enabled && rules.deposit_bonus_eligible?(contact)
            bonus = rules.calculate_bonus(requested_amount)
            if bonus > 0
              Rails.logger.info("[Orchestrator] Auto-bonus: #{bonus} on #{game_slug} for #{contact.name}")
              # Bonus is informational — load already happened at base amount
              # Next iteration: load base+bonus together
            end
          end
        rescue StandardError => e
          Rails.logger.error("[Orchestrator] Auto-bonus check failed: #{e.message}")
        end
        # Check if this deposit qualifies contact for VIP auto-promote
        begin
          Games::TierAutoPromoteService.check(contact: contact)
        rescue StandardError => e
          Rails.logger.error("[Orchestrator] Auto-promote check failed: #{e.message}")
        end
        apply_receipt_preference({
          reply: "loaded $#{requested_amount}#{bonus_note} to #{username} on #{ag.game.name} 🎰 good luck!",
          labels: ['auto-load']
        })
      else
        safe_telegram { Games::TelegramNotifier.load_failed(result[:action]) if result[:action] }
        safe_telegram do
          Games::TelegramNotifier.human_escalation(
            account: account,
            contact: contact,
            reason: escalation_context(
              wants: "$#{fmt_amt(requested_amount)} loaded on #{ag.game.name}",
              done: "payment verified for #{username}; panel load FAILED (#{result[:error]}, code #{result[:code]})",
              left: 'payment received but not loaded',
              suggest: 'retry on the panel once it cooperates',
              need: "load $#{fmt_amt(requested_amount)} for #{username} manually, then confirm in chat"
            ),
            conversation: conversation
          )
        end
        {
          reply: honest_failure_reply(result, requested_amount, ag.game.name),
          labels: ['load-failed', 'needs-human']
        }
      end
    end

    # G1 (June 10) - freeplay on the shared generosity pattern: per-contact
    # override FIRST ('approve' loads now, 'deny' declines politely), the daily
    # per-player limit gates every path, the operator-configured GameRule auto
    # flow stays intact, and the UNCONFIGURED default escalates to Telegram
    # with the full case + a pending ApprovalRequest (approve -> loads through
    # the normal path via Approvals::AutoResume). Every decision is logged.
    def handle_load_freeplay(intent = nil)
      game_slug = chosen_game_slug(intent || { intent: :load })

      unless game_slug
        return { reply: 'which game for freeplay?', labels: [] }
      end

      if contact.player_tier&.blocked?
        return { reply: "sorry, can't process that right now", labels: [] }
      end

      rules = game_rules_for(game_slug)

      fp_override = (contact.custom_attributes || {})['freeplay_auto'].to_s.strip.downcase
      if fp_override == 'deny'
        log_generosity_decision(kind: 'freeplay', decision: 'denied', amount: 0, source: 'contact_override')
        return { reply: "you're maxed out on freeplay right now - load up and keep playing instead", labels: ['freeplay-denied'] }
      end

      fp_amount = freeplay_amount_setting(rules)
      daily_limit = freeplay_daily_limit_setting(rules)
      fp_today = freeplay_given_today

      if fp_today[:count] >= daily_limit
        log_generosity_decision(kind: 'freeplay', decision: 'denied', amount: 0, source: 'daily_limit')
        return { reply: 'you already got your freeplay today! try again tomorrow', labels: ['freeplay-limit'] }
      end

      # MEGA2 P5 - freeplay-farm guard: any freeplay grant needs >= N confirmed
      # real deposits ever (N = account custom_attributes['freeplay_min_deposits'],
      # default 1; 0 disables). Applies to the contact override AND the
      # GameRule auto flow; the operator-approval escalation path (ApprovalRequest
      # -> AutoResume) is an explicit human decision and stays available.
      min_deps = freeplay_min_deposits_setting
      if min_deps.positive?
        real_deps = confirmed_real_deposit_count
        if real_deps < min_deps
          log_generosity_decision(kind: 'freeplay', decision: 'denied', amount: 0, source: 'farm_guard')
          safe_telegram do
            Games::TelegramNotifier.human_escalation(
              account: account, contact: contact,
              reason: escalation_context(
                wants: "$#{fmt_amt(fp_amount)} freeplay on #{game_slug}",
                done: "FARM GUARD: only #{real_deps} confirmed real deposit(s) ever (need #{min_deps}) - NO freeplay granted",
                left: 'no freeplay loaded',
                suggest: 'grant manually only if you know this player',
                need: "approve freeplay for #{contact.name} by hand, or ignore"
              ),
              conversation: conversation
            )
          end
          return { reply: 'freeplay unlocks after your first deposit - load up and i got you', labels: %w[freeplay-denied freeplay-farm-guard] }
        end
      end

      if fp_override == 'approve'
        return execute_freeplay_load(game_slug, fp_amount, rules, source: 'contact_override')
      end

      unless rules&.freeplay_enabled
        # G1b DEFAULT (unconfigured): full case + pending approval, no money yet.
        return escalate_freeplay_ask(game_slug, fp_amount)
      end

      # ---- operator-configured GameRule auto flow (pre-G1 behavior) ----
      unless rules.freeplay_eligible?(contact)
        return { reply: "freeplay isn't available for your account tier right now", labels: [] }
      end

      begin
        week_count = game_actions_for_slug(contact.id, game_slug)
                     .where(action_type: 'load', status: 'success')
                     .where("metadata->>'freeplay' = 'true'")
                     .where('game_actions.created_at >= ?', Time.current.beginning_of_week)
                     .count

        if week_count >= (rules.freeplay_max_per_week || 3)
          log_generosity_decision(kind: 'freeplay', decision: 'denied', amount: 0, source: 'weekly_limit')
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

      execute_freeplay_load(game_slug, fp_amount, rules, source: 'game_rule_auto')
    end

    # ---- G1-G3 (June 10) shared generosity helpers ----

    # Run-1 settings pattern: pref column when it exists -> account
    # custom_attributes -> nil (caller supplies the default).
    def generosity_setting(key)
      pref = reply_pref_cached
      if pref.respond_to?(key)
        v = pref.public_send(key)
        return v if v.present?
      end
      (account.custom_attributes || {})[key.to_s].presence
    rescue StandardError
      nil
    end

    def freeplay_amount_setting(rules)
      tier = begin
        contact.player_tier&.override_for('freeplay_amount')
      rescue StandardError
        nil
      end
      (tier.presence || generosity_setting('freeplay_amount').presence || rules&.freeplay_amount.presence || 5.0).to_f
    end

    # MEGA2 P5 - minimum confirmed real deposits before any freeplay grant.
    # Default 1; explicit 0 disables the guard; garbage values fall back to 1.
    def freeplay_min_deposits_setting
      v = generosity_setting('freeplay_min_deposits')
      return 1 if v.nil? || v.to_s.strip.empty?

      Integer(v.to_s.strip, exception: false) || 1
    rescue StandardError
      1
    end

    # MEGA2 P5 - lifetime confirmed real (non-freeplay) deposits for this
    # contact, account-wide. Fails CLOSED (0) - a DB error must never hand out
    # free money.
    def confirmed_real_deposit_count
      GameAction.where(account_id: account.id, contact_id: contact.id,
                       action_type: 'load', status: 'success')
                .where("COALESCE(metadata->>'freeplay', 'false') != 'true'")
                .count
    rescue StandardError => e
      Rails.logger.error("[Orchestrator] confirmed_real_deposit_count failed: #{e.message}")
      0
    end

    def freeplay_daily_limit_setting(rules)
      v = generosity_setting('freeplay_daily_limit_per_player')
      return v.to_i if v.present? && v.to_i.positive?

      (rules&.freeplay_max_per_day || 1).to_i
    end

    # Per-player, account-wide freeplay given today (count + amount).
    def freeplay_given_today
      scope = GameAction.where(account_id: account.id, contact_id: contact.id,
                               action_type: 'load', status: 'success')
                        .where("metadata->>'freeplay' = 'true'")
                        .where('created_at >= ?', Time.current.beginning_of_day)
      { count: scope.count, amount: scope.sum(:amount).to_f }
    rescue StandardError
      { count: 0, amount: 0.0 }
    end

    # The full case the operator sees: deposits, recency, freeplay today.
    def generosity_case_data(slug = nil)
      base = GameAction.where(account_id: account.id, contact_id: contact.id,
                              action_type: 'load', status: 'success')
      deposits = base.where("COALESCE(metadata->>'freeplay', 'false') != 'true'")
      recent = deposits.where('created_at >= ?', 7.days.ago)
      fp_today = freeplay_given_today
      last_seen = GameAction.where(account_id: account.id, contact_id: contact.id)
                            .order(created_at: :desc).first&.created_at
      {
        total_deposits: deposits.sum(:amount).to_f,
        deposit_count: deposits.count,
        recent_deposits: recent.sum(:amount).to_f,
        recent_count: recent.count,
        fp_today_count: fp_today[:count],
        fp_today_amount: fp_today[:amount],
        days_inactive: last_seen ? ((Time.current - last_seen) / 86_400).floor : nil
      }
    rescue StandardError => e
      Rails.logger.error("[Orchestrator] generosity_case_data failed: #{e.message}")
      { total_deposits: 0.0, deposit_count: 0, recent_deposits: 0.0, recent_count: 0,
        fp_today_count: 0, fp_today_amount: 0.0, days_inactive: nil }
    end

    # WHY-GIVE / WHY-NOT reasons derived from the case data.
    def generosity_reasons(data)
      give = []
      dont = []
      if data[:total_deposits].positive?
        give << "real depositor ($#{fmt_amt(data[:total_deposits])} lifetime, #{data[:deposit_count]} deposits)"
      else
        dont << 'no real deposits ever'
      end
      give << "active this week ($#{fmt_amt(data[:recent_deposits])} across #{data[:recent_count]} loads)" if data[:recent_count].to_i.positive?
      give << "dormant #{data[:days_inactive]}d - a freebie could win them back" if data[:days_inactive].to_i >= 3
      dont << "already got #{data[:fp_today_count]} freeplay today ($#{fmt_amt(data[:fp_today_amount])})" if data[:fp_today_count].to_i.positive?
      dont << 'no activity history at all' if data[:days_inactive].nil?
      [give, dont]
    end

    # D7 - every generosity decision lands on the contact for later analysis.
    def log_generosity_decision(kind:, decision:, amount:, source:)
      attrs = (contact.custom_attributes || {})
      log = Array(attrs['patra_generosity_log'])
      log << { 'kind' => kind, 'decision' => decision, 'amount' => amount.to_f,
               'source' => source, 'at' => Time.current.iso8601 }
      contact.update(custom_attributes: attrs.merge('patra_generosity_log' => log.last(50)))
    rescue StandardError => e
      Rails.logger.error("[Orchestrator] log_generosity_decision failed: #{e.message}")
    end

    # Pending ApprovalRequest (F15 record type) for a generosity payout.
    # Dedupe: one pending request per source+contact. Returns the request,
    # :already, or nil on failure (telegram still carries the case).
    def create_pending_generosity_approval(source:, amount:, game_slug:, username: nil, extra: {})
      already = ApprovalRequest.where(account_id: account.id, action_type: 'load', status: 'pending')
                               .where("metadata->>'source' = ?", source)
                               .where("metadata->>'contact_id' = ?", contact.id.to_s)
                               .exists?
      return :already if already

      ApprovalRequest.create!(
        account: account,
        requesting_user: account.account_users.first&.user,
        action_type: 'load',
        target_type: 'AgentGame',
        target_id: pick_agent_game(game_slug)&.id,
        amount: amount,
        status: 'pending',
        metadata: { 'source' => source, 'contact_id' => contact.id.to_s,
                    'game_slug' => game_slug.to_s, 'game_username' => username.to_s }.merge(extra)
      )
    rescue StandardError => e
      Rails.logger.error("[Orchestrator] create_pending_generosity_approval failed: #{e.message}")
      nil
    end

    # D4 - a rejection in the last 24h makes the next ask a polite decline.
    def recent_generosity_rejection?(source)
      ApprovalRequest.where(account_id: account.id, action_type: 'load', status: 'rejected')
                     .where("metadata->>'source' = ?", source)
                     .where("metadata->>'contact_id' = ?", contact.id.to_s)
                     .where('updated_at >= ?', 24.hours.ago)
                     .exists?
    rescue StandardError
      false
    end

    # G1 - the actual freeplay load (TABA-1 single record, freeplay flag set).
    def execute_freeplay_load(game_slug, fp_amount, rules, source:)
      username = find_game_username_for_slug(contact, game_slug)
      unless username
        return { reply: "I don't have your #{game_slug} account yet - want me to create one?", labels: [] }
      end

      result = execute_game_api(
        game_slug: game_slug,
        action: 'recharge',
        username: username,
        amount: fp_amount.to_i,
        metadata: { freeplay: true, source: 'bella_freeplay', freeplay_decision_source: source, conversation_id: conversation&.id }
      )

      if result[:success]
        log_generosity_decision(kind: 'freeplay', decision: 'given', amount: fp_amount, source: source)
        reply_text = if rules
                       rules.format_message(rules.freeplay_message.presence || 'fp loaded - good luck!', {
                         amount: fp_amount.to_s,
                         game: game_slug
                       })
                     else
                       "loaded $#{fmt_amt(fp_amount)} freeplay - good luck!"
                     end
        begin
          Games::TierAutoPromoteService.check(contact: contact)
        rescue StandardError => e
          Rails.logger.error("[Orchestrator] Auto-promote check failed: #{e.message}")
        end
        apply_receipt_preference({ reply: reply_text, labels: ['freeplay-loaded'] })
      else
        safe_telegram do
          Games::TelegramNotifier.human_escalation(
            account: account, contact: contact,
            reason: escalation_context(
              wants: "$#{fmt_amt(fp_amount)} freeplay on #{game_slug}",
              done: "freeplay approved (#{source}) but the panel load FAILED (#{result[:error]})",
              left: 'freeplay not delivered',
              suggest: 'load it manually once the panel cooperates',
              need: "load $#{fmt_amt(fp_amount)} freeplay for #{username} on #{game_slug}"
            ),
            conversation: conversation
          )
        end
        { reply: "couldn't load freeplay right now - getting someone on it", labels: ['cashier-action-needed'] }
      end
    rescue StandardError => e
      Rails.logger.error("[Orchestrator] Freeplay execution failed: #{e.message}")
      safe_telegram do
        Games::TelegramNotifier.human_escalation(
          account: account, contact: contact,
          reason: escalation_context(
            wants: "$#{fmt_amt(fp_amount)} freeplay on #{game_slug}",
            done: "freeplay path crashed (#{e.class}: #{e.message})",
            left: 'freeplay not delivered',
            suggest: 'check the panel and load manually',
            need: "load $#{fmt_amt(fp_amount)} freeplay for #{contact&.name} on #{game_slug}"
          ),
          conversation: conversation
        )
      end
      { reply: 'having trouble loading that - one sec', labels: ['cashier-action-needed'] }
    end

    # G1b - the unconfigured default: full case to Telegram + pending approval.
    def escalate_freeplay_ask(game_slug, fp_amount)
      if recent_generosity_rejection?('bella_freeplay')
        log_generosity_decision(kind: 'freeplay', decision: 'denied', amount: 0, source: 'operator_reject')
        return { reply: "can't do freeplay for you right now - load up and i'll take care of you on the next one", labels: ['freeplay-denied'] }
      end

      data = generosity_case_data(game_slug)
      give, dont = generosity_reasons(data)
      username = find_game_username_for_slug(contact, game_slug)
      approval = create_pending_generosity_approval(
        source: 'bella_freeplay', amount: fp_amount, game_slug: game_slug,
        username: username, extra: { 'freeplay' => 'true' }
      )

      safe_telegram do
        Games::TelegramNotifier.human_escalation(
          account: account, contact: contact,
          reason: escalation_context(
            wants: "$#{fmt_amt(fp_amount)} freeplay on #{game_slug}",
            done: "case: lifetime deposits $#{fmt_amt(data[:total_deposits])} (#{data[:deposit_count]}), last 7d $#{fmt_amt(data[:recent_deposits])} (#{data[:recent_count]} loads), freeplay today #{data[:fp_today_count]} ($#{fmt_amt(data[:fp_today_amount])}), inactive #{data[:days_inactive] || 'n/a'}d. WHY GIVE: #{give.presence&.join('; ') || 'nothing strong'}. WHY NOT: #{dont.presence&.join('; ') || 'nothing strong'}",
            left: 'no freeplay loaded - waiting on a decision',
            suggest: give.size >= dont.size ? 'lean give' : 'lean decline',
            need: "approve $#{fmt_amt(fp_amount)} freeplay or decline#{approval_ref_text(approval)}"
          ),
          conversation: conversation
        )
      end
      log_generosity_decision(kind: 'freeplay', decision: 'escalated', amount: fp_amount, source: 'default_unconfigured')
      { reply: 'let me check what i can do for you - gimme a few minutes', labels: %w[freeplay-pending needs-human] }
    end

    # G2 - the % bonus that should attach to this deposit. 0.0 when not
    # configured / not qualified. Contact override wins ('none' blocks,
    # a number replaces the account percent).
    def compute_auto_bonus(amount, _slug)
      amt = amount.to_f
      return 0.0 if amt <= 0

      override = (contact.custom_attributes || {})['bonus_percent_override'].to_s.strip
      return 0.0 if override.downcase == 'none'
      return (amt * override.to_f / 100.0).round(2) if override.match?(/\A\d+(\.\d+)?\z/)

      pct = generosity_setting('bonus_percent')
      first_pct = generosity_setting('first_deposit_bonus_percent')
      pct = first_pct if first_pct.present? && first_real_deposit?
      return 0.0 if pct.blank?

      min_dep = generosity_setting('bonus_min_deposit').to_f
      return 0.0 if min_dep.positive? && amt < min_dep

      (amt * pct.to_f / 100.0).round(2)
    rescue StandardError => e
      Rails.logger.error("[Orchestrator] compute_auto_bonus failed: #{e.message}")
      0.0
    end

    def first_real_deposit?
      !GameAction.where(account_id: account.id, contact_id: contact.id,
                        action_type: 'load', status: 'success')
                 .where("COALESCE(metadata->>'freeplay', 'false') != 'true'")
                 .exists?
    rescue StandardError
      false
    end

    def bonus_configured_for_contact?
      override = (contact.custom_attributes || {})['bonus_percent_override'].to_s.strip
      return true if override.match?(/\A\d+(\.\d+)?\z/)

      generosity_setting('bonus_percent').present? || generosity_setting('first_deposit_bonus_percent').present?
    rescue StandardError
      false
    end

    # G2c - explicit bonus ask while UNCONFIGURED: full case + pending approval.
    def escalate_bonus_ask(game_slug)
      if recent_generosity_rejection?('bella_bonus')
        log_generosity_decision(kind: 'bonus', decision: 'denied', amount: 0, source: 'operator_reject')
        return { reply: "no bonus on this one - load up and i'll look out for you next time", labels: ['bonus-denied'] }
      end

      payment = find_unloaded_confirmed_payment
      data = generosity_case_data(game_slug)
      give, dont = generosity_reasons(data)
      username = find_game_username_for_slug(contact, game_slug)
      dep_txt = payment ? "verified $#{fmt_amt(payment[:amount])} deposit waiting" : 'no verified deposit at hand yet'
      approval = create_pending_generosity_approval(
        source: 'bella_bonus', amount: payment ? payment[:amount].to_f : 0,
        game_slug: game_slug, username: username,
        extra: { 'deposit_bonus' => 'true', 'payment_id' => payment ? payment[:id].to_s : '' }
      )

      safe_telegram do
        Games::TelegramNotifier.human_escalation(
          account: account, contact: contact,
          reason: escalation_context(
            wants: "a bonus on their deposit (#{dep_txt})",
            done: "case: lifetime deposits $#{fmt_amt(data[:total_deposits])} (#{data[:deposit_count]}), last 7d $#{fmt_amt(data[:recent_deposits])} (#{data[:recent_count]} loads), inactive #{data[:days_inactive] || 'n/a'}d. WHY GIVE: #{give.presence&.join('; ') || 'nothing strong'}. WHY NOT: #{dont.presence&.join('; ') || 'nothing strong'}",
            left: 'nothing loaded as bonus - bonus settings are unconfigured',
            suggest: 'approve the deposit (add any bonus manually) or set bonus_percent to automate this',
            need: "approve / decline the bonus ask#{approval_ref_text(approval)}"
          ),
          conversation: conversation
        )
      end
      log_generosity_decision(kind: 'bonus', decision: 'escalated', amount: 0, source: 'default_unconfigured')
      { reply: 'let me check what bonus i can do for you - gimme a few minutes', labels: %w[bonus-pending needs-human] }
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
        # G2 (June 10) - no per-game bonus rule. When the new percent settings
        # or the contact override are configured, the normal load path applies
        # the % itself (compute_auto_bonus inside handle_load_intent). An
        # explicit bonus ask while UNCONFIGURED escalates with the full case.
        if bonus_configured_for_contact?
          Rails.logger.info("[Orchestrator] G2 bonus ask: percent settings configured - normal load path applies the bonus")
          return handle_load_intent(intent || { intent: :load, game_slug: game_slug })
        end
        return escalate_bonus_ask(game_slug)
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

      # R7 - over-threshold verified deposits are never auto-loaded, bonus or not.
      bonus_hold = over_threshold_load_hold(payment, game_slug)
      return bonus_hold if bonus_hold

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

        # TAB A fix (same F12 class): deterministic order_id so concurrent
        # duplicates of the SAME payment cannot double-load via the bonus path.
        bonus_order_id = deterministic_payment_order_id(payment[:id])
        return already_loaded_response(deposit_amount) if bonus_order_id.nil?

        result = execute_game_api(
          game_slug: game_slug,
          action: 'recharge',
          username: username,
          amount: total_load.to_i,
          metadata: {
            deposit_bonus: true,
            deposit_amount: deposit_amount,
            bonus_amount: bonus_amount,
            payment_id: payment[:id],
            source: 'bella_bonus'
          },
          order_id: bonus_order_id
        )

        if result[:success]
          # TAB A fix: the executor already audits this load as a GameAction
          # with the metadata above. The old manual GameAction.create! here
          # recorded every bonus load TWICE, double-counting deposits in
          # cashout-multiplier math.
          mark_payment_loaded(payment[:id], game_slug: game_slug, game_username: username)

          reply_text = rules.format_message(rules.deposit_bonus_message || 'Loaded with {bonus_pct}% bonus ✅', {
            amount: deposit_amount.to_s,
            bonus_pct: (rules.deposit_bonus_percentage || 20).to_s,
            bonus_amount: bonus_amount.to_s,
            total: total_load.to_s,
            game: game_slug
          })
          # Check if this deposit qualifies contact for VIP auto-promote
          begin
            Games::TierAutoPromoteService.check(contact: contact)
          rescue StandardError => e
            Rails.logger.error("[Orchestrator] Auto-promote check failed: #{e.message}")
          end
          apply_receipt_preference({ reply: reply_text, labels: ['auto-load'] })
        else
          safe_telegram do
            Games::TelegramNotifier.human_escalation(
              account: account, contact: contact,
              reason: escalation_context(
                wants: "deposit + bonus loaded on #{game_slug} ($#{fmt_amt(total_load)} total)",
                done: 'bonus qualified but the panel load FAILED',
                left: 'deposit and bonus both unloaded',
                suggest: 'load the total manually on the panel',
                need: "load $#{fmt_amt(total_load)} for #{contact.name} and confirm in chat"
              ),
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
            reason: escalation_context(
              wants: 'a bonus-load on their deposit',
              done: "bonus path crashed (#{e.message})",
              left: 'deposit not loaded',
              suggest: 'check the ledger and load manually',
              need: "sort the bonus load for #{contact.name} and confirm in chat"
            ),
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

      # Feature 3 — cashout velocity guard. Only blocks ABOVE threshold.
      cashout_vel = cashout_velocity_state
      if cashout_vel[:exceeded]
        safe_telegram do
          Games::TelegramNotifier.human_escalation(
            account: account, contact: contact,
            reason: escalation_context(
              wants: 'another cashout',
              done: "VELOCITY FLAG: #{cashout_vel[:count]} successful cashouts in the last #{cashout_vel[:hours]}h (threshold #{cashout_vel[:threshold]}) - this one was HELD",
              left: 'the held cashout request',
              suggest: 'eyeball the pattern for fraud before releasing',
              need: 'clear or decline this cashout'
            ),
            conversation: conversation
          )
        end
        return { reply: 'let me have a teammate check this one.', labels: %w[velocity-flag needs-human] }
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

      # Parse requested amount: detector-verified amount first, then the number
      # right after a cashout verb, then (legacy) the first number in the text.
      # TAB A fix: first-number parsing took the wrong amount on messages like
      # "keep 30 in and cash out 50" (it took 30, the keep-in amount).
      requested_amount = (intent.is_a?(Hash) && intent[:amount].to_f > 0) ? intent[:amount].to_f : nil
      if requested_amount.nil?
        msg = (latest_customer_text || recent_customer_text).to_s
        verb_m = msg.match(/(?:cash\s*out|cashout|redeem|withdraw|payout|take\s+out)\s+\$?(\d+(?:\.\d{1,2})?)/i)
        requested_amount = verb_m ? verb_m[1].to_f : msg.scan(/\$?(\d+(?:\.\d{1,2})?)/).flatten.first&.to_f
      end

      # R3 (June 10) - min/max come from the LAST deposit, not the lifetime sum.
      # The last deposit's TYPE picks the rule fields when the rule layer has
      # type-specific ones (freeplay does: cashout_freeplay_multiplier/max);
      # deposit/bonus/referral/keep-in use the default multipliers.
      if rules
        begin
          last_dep = last_deposit_for_cashout(game_slug)

          if last_dep && last_dep[:type] == 'freeplay'
            min_cashout = last_dep[:amount] * (rules.cashout_freeplay_multiplier || 5).to_f
            max_cashout = (rules.cashout_freeplay_max || 50).to_f
          elsif last_dep
            min_cashout = last_dep[:amount] * (rules.cashout_min_multiplier || 4).to_f
            max_cashout = [last_dep[:amount] * (rules.cashout_max_multiplier || 10).to_f, (rules.cashout_max_amount || 250).to_f].min
          else
            # No load history at all - keep the legacy conservative cap.
            min_cashout = 0.0
            max_cashout = (rules.cashout_freeplay_max || 50).to_f
          end

          # Validate requested amount
          if requested_amount
            if requested_amount < (rules.cashout_min_amount || 10)
              return {
                reply: "minimum cashout is $#{(rules.cashout_min_amount || 10).to_i}",
                labels: []
              }
            end

            # R3 - below the multiplier minimum: state the REAL minimum.
            if last_dep && min_cashout > 0 && requested_amount < min_cashout
              return {
                reply: "min cashout on a $#{fmt_amt(last_dep[:amount])} #{last_dep[:type]} is $#{fmt_amt(min_cashout)}",
                labels: []
              }
            end

            # R4 - over the max is no longer a flat decline; the overmax mode
            # decides what the player is told and what the cashier is asked to do.
            if requested_amount > max_cashout
              return handle_over_max_cashout(game_slug, requested_amount, max_cashout, last_dep)
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

      # Check confirm-before-cashout preference
      begin
        pref = ReplyPreference.for_account(account.id)
        if pref&.confirm_before_cashout
          unless conversation.additional_attributes&.dig('cashout_confirmed')
            attrs = (conversation.additional_attributes || {}).merge('pending_cashout' => game_slug)
            conversation.update_columns(additional_attributes: attrs)
            return {
              reply: requested_amount ? "confirm cashout $#{requested_amount.to_i} on #{game_slug}? (yes/no)" : "confirm cashout on #{game_slug}? (yes/no)",
              labels: []
            }
          end
        end
      rescue StandardError => e
        Rails.logger.error("[Orchestrator] Confirm-before-cashout check failed: #{e.message}")
      end

      # All checks passed — escalate to cashier for actual payout
      amount_text = requested_amount ? "$#{requested_amount.to_i}" : "cashout"
      begin
        Games::TelegramNotifier.human_escalation(
          account: account,
          contact: contact,
          reason: escalation_context(
            wants: "cashout #{amount_text} on #{game_slug}",
            done: 'all checks passed (rules, velocity, dedup) - payout is cashier-manual',
            left: 'the payout itself',
            suggest: 'verify the balance on the panel, then pay',
            need: "send #{amount_text} to #{contact.name} and confirm in chat"
          ),
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

      # R7 - verified deposits above the auto-load threshold need a human first.
      up_hold = over_threshold_load_hold(recent_payment, ag.game.name)
      return up_hold if up_hold

      executor = Games::ActionExecutor.new(agent_game: ag, contact: contact, conversation: conversation)

      # First try to load — if user doesn't exist, auto-create
      # F12: deterministic order_id (see handle_load_intent).
      up_order_id = deterministic_payment_order_id(recent_payment[:id])
      return already_loaded_response(recent_payment[:amount]) if up_order_id.nil?

      result = begin
        executor.load_player(
          game_username: username,
          amount: recent_payment[:amount],
          payment_method: recent_payment[:method],
          metadata: { source: 'bella_username_provided', payment_id: recent_payment[:id] },
          order_id: up_order_id
        )
      rescue Games::ActionExecutor::IdempotencyError, ActiveRecord::RecordNotUnique
        return already_loaded_response(recent_payment[:amount])
      end

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
              reason: escalation_context(
                wants: "their $#{fmt_amt(recent_payment[:amount])} payment loaded (new username #{username})",
                done: "account creation FAILED (#{add_result[:error]})",
                left: 'no account, payment not loaded',
                suggest: 'create the account manually, then load',
                need: "create #{username} and load $#{fmt_amt(recent_payment[:amount])}, then confirm in chat"
              ),
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

        up_retry_order_id = deterministic_payment_order_id(recent_payment[:id])
        return already_loaded_response(recent_payment[:amount]) if up_retry_order_id.nil?

        result = begin
          executor.load_player(
            game_username: username,
            amount: recent_payment[:amount],
            payment_method: recent_payment[:method],
            metadata: { source: 'bella_username_after_create', payment_id: recent_payment[:id] },
            order_id: up_retry_order_id
          )
        rescue Games::ActionExecutor::IdempotencyError, ActiveRecord::RecordNotUnique
          return already_loaded_response(recent_payment[:amount])
        end

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
            reason: escalation_context(
              wants: "their $#{fmt_amt(recent_payment[:amount])} payment loaded on #{ag.game.name}",
              done: "username confirmed (#{username}); panel load FAILED (#{result[:error]})",
              left: 'payment received but not loaded',
              suggest: 'retry the load on the panel',
              need: "load $#{fmt_amt(recent_payment[:amount])} for #{username} manually, then confirm in chat"
            ),
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

      # R6b (June 10) - existing account + asks to create: ASK, don't assume.
      # The answer ("use that one" / "make a new one") is handled next turn via
      # resolve_pending_account_choice. NO DUPLICATE ACCOUNTS unless they choose new.
      existing_username = verified_stored_game_username(ag)
      if existing_username.present? && !wants_replace
        store_pending_account_choice(ag.game.slug)
        return {
          reply: "you've already got a #{ag.game.name} account (#{existing_username}) - want to use that one, or make a new one?",
          labels: ['account-exists', 'account-choice-pending']
        }
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
              reason: escalation_context(
                wants: "a #{ag.game.name} account",
                done: "auto-create FAILED after retries (#{add_result[:error]}) - no payment at stake yet",
                left: 'player has no account',
                suggest: 'create one manually and send the creds',
                need: "a working #{ag.game.name} account for #{contact.name}"
              ),
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

        result = {
          reply: "all set! your username: #{auto_username}, password: #{generated_password} (save this!) — #{payment_methods_question}",
          labels: ['account-created', 'awaiting-payment']
        }
        # Assign new_player tier to first-time contacts
        begin
          Games::TierAutoPromoteService.assign_new_player_tier(contact: contact)
        rescue StandardError => e
          Rails.logger.error("[Orchestrator] New player tier assign failed: #{e.message}")
        end
        link_referred_on_account_creation
        # Send game download link if configured
        begin
          game = Game.find_by(slug: game_slug) if game_slug
          rules = game ? GameRule.find_by(account_id: account.id, game_id: game.id) : nil
          if rules&.auto_send_link_on_create && rules.game_download_url.present?
            result[:reply] += "\n#{rules.game_download_url}"
          end
        rescue StandardError => e
          Rails.logger.error("[Orchestrator] Download link append failed: #{e.message}")
        end
        return result
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
            reason: escalation_context(
              wants: "a #{ag.game.name} account + their $#{fmt_amt(recent_payment[:amount])} loaded",
              done: "payment verified; auto-create FAILED after retries (#{add_result[:error]})",
              left: 'no account, payment not loaded',
              suggest: 'create the account manually, then load the payment',
              need: "account + $#{fmt_amt(recent_payment[:amount])} load for #{contact.name}, then confirm in chat"
            ),
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

      # R7 - account IS created (no deposit gate, R6a), but a verified deposit
      # above the threshold is NOT auto-loaded; the hold path takes over.
      ac_hold = over_threshold_load_hold(recent_payment, ag.game.name)
      if ac_hold
        ac_hold = ac_hold.dup
        ac_hold[:reply] = "all set! username: #{auto_username}, password: #{generated_password} (save this!) - #{ac_hold[:reply]}"
        ac_hold[:labels] = (Array(ac_hold[:labels]) + ['account-created']).uniq
        return ac_hold
      end

      # Load the payment.
      # TAB A fix: this was the 5th automated payment-load site and the only
      # one missed by F12 - without the deterministic order_id, two concurrent
      # "create my account" messages could double-load the same payment.
      ac_order_id = deterministic_payment_order_id(recent_payment[:id])
      if ac_order_id.nil?
        return {
          reply: "all set! username: #{auto_username}, password: #{generated_password} (save this!) \u{2014} your $#{fmt_amt(recent_payment[:amount])} load already went through \u{1F3B0}",
          labels: ['account-created', 'auto-load', 'new-account-created']
        }
      end

      result = begin
        executor.load_player(
          game_username: auto_username,
          amount: recent_payment[:amount],
          payment_method: recent_payment[:method],
          metadata: { source: 'bella_account_created', payment_id: recent_payment[:id] },
          order_id: ac_order_id
        )
      rescue Games::ActionExecutor::IdempotencyError, ActiveRecord::RecordNotUnique
        return {
          reply: "all set! username: #{auto_username}, password: #{generated_password} (save this!) \u{2014} your $#{fmt_amt(recent_payment[:amount])} load already went through \u{1F3B0}",
          labels: ['account-created', 'auto-load', 'new-account-created']
        }
      end

      if result[:ok]
        mark_payment_loaded(recent_payment[:id], game_slug: ag.game.slug, game_username: auto_username)
        result = {
          reply: "all set! username: #{auto_username}, password: #{generated_password} (save this!) — loaded $#{recent_payment[:amount]} 🎰 good luck!",
          labels: ['auto-load', 'new-account-created']
        }
        # Assign new_player tier to first-time contacts
        begin
          Games::TierAutoPromoteService.assign_new_player_tier(contact: contact)
        rescue StandardError => e
          Rails.logger.error("[Orchestrator] New player tier assign failed: #{e.message}")
        end
        link_referred_on_account_creation
        # Send game download link if configured
        begin
          game = Game.find_by(slug: game_slug) if game_slug
          rules = game ? GameRule.find_by(account_id: account.id, game_id: game.id) : nil
          if rules&.auto_send_link_on_create && rules.game_download_url.present?
            result[:reply] += "\n#{rules.game_download_url}"
          end
        rescue StandardError => e
          Rails.logger.error("[Orchestrator] Download link append failed: #{e.message}")
        end
        apply_receipt_preference(result)
      else
        safe_telegram { Games::TelegramNotifier.load_failed(result[:action]) if result[:action] }
        safe_telegram do
          Games::TelegramNotifier.human_escalation(
            account: account, contact: contact,
            reason: escalation_context(
              wants: "their $#{fmt_amt(recent_payment[:amount])} loaded on the fresh account",
              done: "account #{auto_username} CREATED, creds sent; load FAILED (#{result[:error]})",
              left: 'payment not loaded',
              suggest: 'load it on the panel - account already exists',
              need: "load $#{fmt_amt(recent_payment[:amount])} to #{auto_username}, then confirm in chat"
            ),
            conversation: conversation
          )
        end
        result = {
          reply: "created your account! username: #{auto_username}, password: #{generated_password} (save this!) — but hit a snag loading your $#{recent_payment[:amount]}. a teammate will load it in a couple minutes.",
          labels: ['account-created', 'load-failed', 'needs-human']
        }
        # Assign new_player tier to first-time contacts
        begin
          Games::TierAutoPromoteService.assign_new_player_tier(contact: contact)
        rescue StandardError => e
          Rails.logger.error("[Orchestrator] New player tier assign failed: #{e.message}")
        end
        link_referred_on_account_creation
        # Send game download link if configured
        begin
          game = Game.find_by(slug: game_slug) if game_slug
          rules = game ? GameRule.find_by(account_id: account.id, game_id: game.id) : nil
          if rules&.auto_send_link_on_create && rules.game_download_url.present?
            result[:reply] += "\n#{rules.game_download_url}"
          end
        rescue StandardError => e
          Rails.logger.error("[Orchestrator] Download link append failed: #{e.message}")
        end
        result
      end
    end

    # ---- R6 (June 10) - use-old / make-new choice + the failure ladder ----
    # Ladder order: resend -> reset password -> create new account -> suggest a
    # different game -> Telegram human. On each rung's FAILURE we fall to the
    # next rung instead of dead-ending. Explicit new-account requests enter at
    # the create rung; access problems enter at resend/reset.

    def store_pending_account_choice(slug)
      attrs = (contact.custom_attributes || {}).merge(
        'pending_account_choice' => { 'game_slug' => slug, 'set_at' => Time.current.iso8601 }
      )
      contact.update(custom_attributes: attrs)
    rescue StandardError => e
      Rails.logger.error("[Orchestrator] store_pending_account_choice failed: #{e.message}")
    end

    def clear_pending_account_choice
      attrs = (contact.custom_attributes || {}).dup
      attrs.delete('pending_account_choice')
      contact.update(custom_attributes: attrs)
    rescue StandardError => e
      Rails.logger.error("[Orchestrator] clear_pending_account_choice failed: #{e.message}")
    end

    # Returns a response hash when the answer resolves the choice, nil to fall
    # through to normal intent handling. Stale flags (>30 min) are cleared.
    def resolve_pending_account_choice(answer_text, pending)
      pending = pending.is_a?(Hash) ? pending.stringify_keys : {}
      slug = pending['game_slug']
      set_at = pending['set_at']
      fresh = set_at.blank? || begin
        Time.parse(set_at) > 30.minutes.ago
      rescue StandardError
        true
      end
      unless fresh && slug.present?
        clear_pending_account_choice
        return nil
      end

      answer = answer_text.to_s.downcase
      wants_new = answer.match?(/\b(new|fresh|another|different|make)\b/)
      wants_old = answer.match?(/\b(old|same|that one|use it|keep it|first one|existing)\b/) ||
                  answer.match?(/\buse\b.*\b(that|it|old|same)\b/)
      return nil unless wants_new || wants_old

      clear_pending_account_choice
      ag = pick_agent_game(slug)
      return { reply: unavailable_game_reply(slug), labels: ['game-unavailable'] } unless ag

      if wants_new && !wants_old
        # make-new: fresh account, vault creds swapped; old stays on the panel.
        clear_game_credentials(ag.game.slug)
        return handle_account_creation_request(intent: :request_account_creation, game_slug: ag.game.slug)
      end

      resend_or_reset_credentials(ag)
    end

    # Rungs 1-2: resend stored creds when we have both; with a username but no
    # password, reset to mint fresh creds; with nothing stored, create new.
    def resend_or_reset_credentials(ag)
      username = stored_game_username(ag.game.slug)
      password = stored_game_password(ag.game.slug)

      if username.present? && password.present?
        return {
          reply: "here you go - #{ag.game.name} username: #{username}, password: #{password} (save this!)",
          labels: ['credentials-resent']
        }
      end

      return reset_password_with_ladder(ag, username) if username.present?

      handle_account_creation_request(intent: :request_account_creation, game_slug: ag.game.slug)
    end

    # Rung 2 (reset password); on failure walks DOWN to create-new.
    def reset_password_with_ladder(ag, username)
      new_password = generate_reset_password(ag.game.slug)
      executor = Games::ActionExecutor.new(agent_game: ag, contact: contact, conversation: conversation)
      result = begin
        executor.reset_player_password(
          game_username: username,
          new_password: new_password,
          metadata: { source: 'bella_ladder_reset', conversation_id: conversation&.id }
        )
      rescue StandardError => e
        { ok: false, error: e.message }
      end

      if result[:ok]
        store_game_password(ag.game.slug, new_password)
        return {
          reply: "your #{ag.game.name} login: #{username}, new password: #{new_password} (save this!)",
          labels: ['password-reset']
        }
      end

      Rails.logger.warn("[Orchestrator] ladder: reset failed on #{ag.game.slug} (#{result[:error]}) - trying a fresh account")
      create_new_account_with_ladder(ag, after: "password reset failed (#{result[:error]})")
    end

    # Rung 3 (create new). On failure: rung 4 suggest a different game + rung 5
    # Telegram the human with the full R8 context. Never a dead-end.
    def create_new_account_with_ladder(ag, after: nil)
      clear_game_credentials(ag.game.slug)
      executor = Games::ActionExecutor.new(agent_game: ag, contact: contact, conversation: conversation)
      add_result, auto_username, = attempt_auto_add_player(executor, ag.game.slug, metadata: { source: 'bella_ladder_create' })

      if add_result[:ok]
        generated_password = add_result[:password]
        store_game_username(ag.game.slug, auto_username)
        store_game_password(ag.game.slug, generated_password)
        return {
          reply: "all set! your new #{ag.game.name} account - username: #{auto_username}, password: #{generated_password} (save this!)",
          labels: ['new-account-created']
        }
      end

      ladder_end_response(ag, after: [after, "account creation failed (#{add_result[:error]})"].compact.join('; '))
    end

    # Rungs 4-5: suggest a different game AND Telegram the human (R8 context).
    def ladder_end_response(ag, after: nil)
      others = active_game_names.reject { |n| n == ag.game.name }
      suggestion = others.any? ? "want to hop on #{others.first} instead while we fix it?" : 'a teammate is on it.'
      safe_telegram do
        Games::TelegramNotifier.human_escalation(
          account: account, contact: contact,
          reason: escalation_context(
            wants: "a working #{ag.game.name} account",
            done: after.to_s,
            left: "player still has no working #{ag.game.name} login",
            suggest: others.any? ? "offered the player #{others.first} meanwhile" : 'no other active game to offer',
            need: "fix or create the #{ag.game.name} account manually, then send the player their creds"
          ),
          conversation: conversation
        )
      end
      {
        reply: "#{ag.game.name} is being stubborn right now - #{suggestion} i've flagged a teammate to sort your account either way.",
        labels: ['account-creation-failed', 'needs-human', 'ladder-exhausted']
      }
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
            reason: escalation_context(
              wants: "a #{ag.game.name} account",
              done: "panel said OK but verification shows NO account (silent fail: #{add_result[:error]}) - credentials NOT stored",
              left: 'player has no working account',
              suggest: 'check the panel by hand - this panel lies about creates',
              need: "a verified working account for #{contact.name}"
            ),
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
            reason: escalation_context(
              wants: "a #{ag.game.name} account",
              done: 'account creation timed out after 45s - unknown panel state',
              left: 'account may or may not exist on the panel',
              suggest: 'check the panel before retrying (avoid a duplicate)',
              need: "confirm/create the account for #{contact.name} and send creds"
            ),
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

    # F12: deterministic order_id for PAYMENT-MATCHED automated loads.
    # Same payment identity => same base, so N concurrent duplicates collapse
    # on the DB unique index game_actions(account_id, order_id) - the
    # payment_already_loaded? check is check-then-act and cannot stop a true
    # race. success/pending blocks re-execution (returns nil = already
    # loaded); failed attempts free the base via the attempt suffix so the
    # code-8 auto-create retry still works. Manual / freeplay / bonus loads
    # keep their original random scheme (this is only called with a payment).
    def deterministic_payment_order_id(payment_id)
      base = "pay#{Digest::SHA1.hexdigest("#{account.id}:#{contact&.id}:#{payment_id}")[0, 20]}"
      existing = GameAction.where(account_id: account.id).where('order_id LIKE ?', "#{base}%")
      # MEGA2 P6 - 'ambiguous' (panel MAY have credited) blocks automatic
      # re-execution exactly like success/pending; only a human redo after a
      # balance check may move this payment again.
      return nil if existing.where(status: %w[success pending ambiguous]).exists?

      "#{base}_a#{existing.count}"
    end

    def already_loaded_response(amount)
      Rails.logger.info("[Orchestrator] duplicate load suppressed (deterministic order_id) conv=#{conversation&.id} amount=#{amount}")
      { reply: "you're all set — that $#{fmt_amt(amount)} load already went through \u{1F3B0}", labels: ['auto-load'] }
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
        # R6c - reset failed: fall to the next rung (create a fresh account)
        # instead of dead-ending at "flagged a teammate".
        Rails.logger.warn("[Orchestrator] reset failed on #{ag.game.name} for #{username}: #{result[:error]} - walking the ladder")
        create_new_account_with_ladder(ag, after: "password reset failed (#{result[:error]})")
      end
    end

    # S3 (June 10) - "i sent it": check the EMAIL payment records and only ever
    # load on a verified match (sender name + amount + time within
    # PATRA_PAYMENT_MATCH_WINDOW_MINUTES, default 10). Sender-name memory lives
    # on the contact (asked once, remembered after). Two consecutive misses,
    # then a third insist -> escalate with the full R8 context.
    # NEVER loads without a verified email match.
    def handle_payment_sent_confirmation(intent)
      # Refresh the email records via the existing IMAP ownership path.
      begin
        if defined?(Payments::EmailConfirmationService)
          Payments::EmailConfirmationService.new(contact: contact).check_all
          contact.reload
        end
      rescue StandardError => e
        Rails.logger.error("[Orchestrator] IMAP trigger failed: #{e.message}")
      end

      claim = extract_payment_claim
      sender_name = claim[:sender_name].presence || remembered_sender_name

      # No name from message, screenshot OCR, or memory -> ask for it (and the
      # screenshot when there is none). Asking is not a miss.
      if sender_name.blank?
        ask = "what name did you send it from? i'll match it up"
        ask += ' - and drop the screenshot here too' unless claim[:has_screenshot]
        return { reply: ask, labels: ['payment-pending', 'needs-sender-name'] }
      end

      matched = find_verified_email_payment(claim[:amount], sender_name, claim[:claimed_at])

      if matched
        matched_amount = parse_amount(matched['email_amount'].presence || matched['amount'])

        if payment_entry_already_loaded?(matched)
          return { reply: "that $#{fmt_amt(matched_amount)} payment was already loaded - nothing new to add. anything else?", labels: ['payment-already-loaded'] }
        end

        remember_sender_name(matched['email_sender_name'].presence || sender_name)
        reset_payment_miss_counter
        Rails.logger.info("[Orchestrator] payment-sent: verified email match $#{matched_amount} (#{sender_name}) - loading via the normal path")
        completion = handle_load_intent({ intent: :load, amount: matched_amount, game_slug: chosen_game_slug(intent), game_username: nil })
        return completion if completion.is_a?(Hash) && completion[:reply].present?

        return { reply: "your $#{fmt_amt(matched_amount)} is verified - which game do you want it on?", labels: ['payment-verified'] }
      end

      # A verified email exists for the amount/time but under a different name:
      # ask for the name once instead of burning a miss.
      if sender_mismatch_candidate?(claim[:amount], claim[:claimed_at], sender_name)
        return { reply: 'i see a payment but under a different name - what name did you send it from?', labels: ['payment-pending', 'needs-sender-name'] }
      end

      misses = increment_payment_miss_counter
      if misses > 2
        safe_telegram do
          Games::TelegramNotifier.human_escalation(
            account: account, contact: contact,
            reason: escalation_context(
              wants: "credit for a payment they say they sent#{claim[:amount] ? " ($#{fmt_amt(claim[:amount])})" : ''}",
              done: "checked the email records #{misses} times - no verified match for '#{sender_name}' within #{payment_match_window_minutes} min",
              left: 'nothing loaded - no verified email match exists',
              suggest: 'check the payment app and inbox by hand',
              need: 'confirm whether the money actually landed, then load or decline'
            ),
            conversation: conversation
          )
        end
        return { reply: "i still don't see it on our end - flagged a teammate to dig in, they'll sort you out shortly.", labels: %w[payment-unverified needs-human] }
      end

      reply = if claim[:has_screenshot]
                "don't see it on our end yet - payments can take a few minutes to land. mind double-checking the name and exact amount you sent?"
              else
                "don't see it on our end yet - payments can take a few minutes to land. drop the screenshot here and i'll match it up."
              end
      { reply: reply, labels: ['payment-pending'] }
    end

    # ---- S3 (June 10) - payment-sent matching helpers ----

    # Minutes allowed between the claimed/screenshot time and the email time.
    def payment_match_window_minutes
      v = ENV['PATRA_PAYMENT_MATCH_WINDOW_MINUTES'].to_i
      v.positive? ? v : 10
    end

    def remembered_sender_name
      (contact.custom_attributes || {})['payment_sender_name'].presence
    end

    def remember_sender_name(name)
      return if name.to_s.strip.blank?

      attrs = (contact.custom_attributes || {}).merge('payment_sender_name' => name.to_s.strip)
      contact.update(custom_attributes: attrs)
    rescue StandardError => e
      Rails.logger.error("[Orchestrator] remember_sender_name failed: #{e.message}")
    end

    # Miss counter lives on the conversation; contact fallback when the
    # conversation is nil (some API paths + the harness). See log D3.
    def payment_miss_count
      if conversation
        (conversation.additional_attributes || {})['payment_match_misses'].to_i
      else
        (contact.custom_attributes || {})['payment_match_misses'].to_i
      end
    rescue StandardError
      0
    end

    def set_payment_miss_count(value)
      if conversation
        attrs = (conversation.additional_attributes || {}).merge('payment_match_misses' => value)
        conversation.update_columns(additional_attributes: attrs)
      else
        attrs = (contact.custom_attributes || {}).merge('payment_match_misses' => value)
        contact.update(custom_attributes: attrs)
      end
    rescue StandardError => e
      Rails.logger.error("[Orchestrator] set_payment_miss_count failed: #{e.message}")
    end

    def increment_payment_miss_counter
      n = payment_miss_count + 1
      set_payment_miss_count(n)
      n
    end

    def reset_payment_miss_counter
      set_payment_miss_count(0)
    end

    # S3 - what the player claims they sent: amount + sender name from the
    # message text, enriched by the newest screenshot-derived ledger entry
    # (OCR fields written by the existing vision path). Never raises.
    def extract_payment_claim
      text = (latest_customer_text || recent_customer_text).to_s
      amount = text.match(/\$?\s*(\d+(?:\.\d{1,2})?)/)&.[](1)&.to_f
      amount = nil unless amount&.positive?
      name = nil
      if (m = text.match(/(?:from|under|name(?:'?s)?(?:\s+is)?)\s+([a-z][a-z\s'.\-]{1,40})/i))
        name = m[1].strip
      end
      name = nil if name && %w[cashapp cash venmo chime paypal zelle].include?(name.downcase)

      claimed_at = Time.current
      entry = newest_screenshot_log_entry
      if entry
        amount ||= parse_amount(entry['amount'])
        name = entry['sender_name'].presence if name.blank?
        shot_time = parse_time(entry['image_received_at'].presence || entry['recorded_at'])
        claimed_at = shot_time if shot_time
      end

      { amount: amount, sender_name: name, claimed_at: claimed_at, has_screenshot: entry.present? }
    rescue StandardError => e
      Rails.logger.error("[Orchestrator] extract_payment_claim failed: #{e.message}")
      { amount: nil, sender_name: nil, claimed_at: Time.current, has_screenshot: false }
    end

    def newest_screenshot_log_entry
      logs = (contact.custom_attributes || {})['patra_finance_logs']
      return nil unless logs.is_a?(Array)

      logs.reverse_each do |log|
        next unless log.is_a?(Hash)
        next if log['image_url'].blank?

        t = parse_time(log['image_received_at'].presence || log['recorded_at'])
        next if t && t < 1.hour.ago

        return log
      end
      nil
    end

    # S3 - newest email-verified, unflagged ledger entry matching amount (when
    # given), sender name (when given), and the time window. Returns the raw
    # entry Hash or nil. Never raises.
    def find_verified_email_payment(amount, sender_name, claimed_at)
      logs = (contact.custom_attributes || {})['patra_finance_logs']
      return nil unless logs.is_a?(Array)

      window = payment_match_window_minutes.minutes
      logs.reverse_each do |log|
        next unless log.is_a?(Hash)
        next unless log['email_confirmed'] == true
        next if log['flag_reason'].to_s.strip.present?

        log_amount = parse_amount(log['email_amount'].presence || log['amount'])
        next if log_amount.nil?
        next if amount && (log_amount - amount.to_f).abs > 0.01

        if sender_name.present?
          email_name = (log['email_sender_name'].presence || log['sender_name']).to_s
          next if email_name.blank?
          next unless names_overlap_loose?(email_name, sender_name)
        end

        email_time = parse_time(log['email_date'].presence || log['email_confirmed_at'].presence || log['recorded_at'])
        next if email_time && claimed_at && (email_time - claimed_at).abs > window

        return log
      end
      nil
    rescue StandardError => e
      Rails.logger.error("[Orchestrator] find_verified_email_payment failed: #{e.message}")
      nil
    end

    # S3 - a verified email matches amount+time but carries a different sender
    # name (and was not already loaded) -> worth asking for the name.
    def sender_mismatch_candidate?(amount, claimed_at, sender_name)
      entry = find_verified_email_payment(amount, nil, claimed_at)
      return false unless entry

      email_name = (entry['email_sender_name'].presence || entry['sender_name']).to_s
      email_name.present? && !names_overlap_loose?(email_name, sender_name) && !payment_entry_already_loaded?(entry)
    rescue StandardError
      false
    end

    def payment_entry_already_loaded?(log)
      return true if log['status'].to_s.downcase == 'loaded'
      return true if log['game_load_success'] == true

      log_id = log['id'].presence || log['transaction_id'].presence || log['image_url'].presence || "#{log['amount']}_#{log['recorded_at']}"
      payment_already_loaded?(log_id, parse_amount(log['amount']), parse_time(log['recorded_at']))
    rescue StandardError
      false
    end

    # Local first-token-overlap check (EmailConfirmationService's version is a
    # private class method - see log D7).
    def names_overlap_loose?(a, b)
      a = a.to_s.downcase.strip
      b = b.to_s.downcase.strip
      return false if a.blank? || b.blank?
      return true if a.include?(b) || b.include?(a)

      a_first = a.split(/\s+/).first
      b_first = b.split(/\s+/).first
      (a_first.present? && b.include?(a_first)) || (b_first.present? && a.include?(b_first))
    end

    # S1 (June 10) - real status check. Order: (c) finish verifiable undone work
    # through the NORMAL load path (F12 order_id + R7 threshold + approval gates
    # all apply; a redo of done work no-ops via the F12 guard), then (a) report
    # the most recent action's REAL recorded state - no speculative paid panel
    # calls, recorded status + stored creds only - then (d) nothing pending ->
    # ask what they need, (e) on error escalate with the full R8 context.
    def handle_status_check(intent)
      game_slug = chosen_game_slug(intent) || (contact.custom_attributes || {})['preferred_platform']
      labels = ['status-check']

      begin
        # (c) a verified payment that never got loaded is finishable work.
        pending_payment = find_unloaded_confirmed_payment
        if pending_payment
          Rails.logger.info("[Orchestrator] status-check: unloaded verified payment $#{pending_payment[:amount]} - completing via the normal load path")
          completion = handle_load_intent({ intent: :load, amount: pending_payment[:amount].to_f, game_slug: game_slug, game_username: nil })
          if completion.is_a?(Hash) && completion[:reply].present?
            completion = completion.dup
            completion[:labels] = (Array(completion[:labels]) + labels).uniq
            return completion
          end
        end

        # (b) scan the ~50-message window for a load ask that never completed.
        unresolved = unresolved_load_ask_from_window
        if unresolved
          Rails.logger.info("[Orchestrator] status-check: unresolved load ask $#{unresolved[:amount]} - re-running the normal load path")
          completion = handle_load_intent({ intent: :load, amount: unresolved[:amount], game_slug: unresolved[:game_slug] || game_slug, game_username: nil })
          if completion.is_a?(Hash) && completion[:reply].present?
            completion = completion.dup
            completion[:labels] = (Array(completion[:labels]) + labels).uniq
            return completion
          end
        end

        # (a) report the REAL recorded state of the most recent action.
        scope = GameAction.where(account_id: account.id, contact_id: contact.id)
        scope = scope.joins(agent_game: :game).where(games: { slug: game_slug }) if game_slug.present?
        last_action = scope.order(created_at: :desc).first

        if last_action
          action_slug = last_action.agent_game&.game&.slug || game_slug
          when_txt = time_ago_phrase(last_action.created_at)
          case last_action.status
          when 'success'
            reply =
              if last_action.action_type == 'add_player'
                ready_username = stored_game_username(action_slug).presence || last_action.game_username
                "your #{slug_label(action_slug)} account is ready - username #{ready_username}. anything else?"
              else
                amt_txt = last_action.amount.to_f > 0 ? "$#{fmt_amt(last_action.amount)} " : ''
                "your last #{last_action.action_type} #{amt_txt}on #{slug_label(action_slug)} went through #{when_txt} - you're all set"
              end
          when 'pending'
            amt_txt = last_action.amount.to_f > 0 ? " for $#{fmt_amt(last_action.amount)}" : ''
            reply = "your #{last_action.action_type}#{amt_txt} on #{slug_label(action_slug)} is still processing (started #{when_txt}) - i'll update you the second it lands"
          when 'failed'
            labels << 'cashier-action-needed'
            safe_telegram do
              Games::TelegramNotifier.human_escalation(
                account: account, contact: contact,
                reason: escalation_context(
                  wants: "status of their #{last_action.action_type} on #{action_slug}",
                  done: "checked records: last #{last_action.action_type} $#{fmt_amt(last_action.amount)} FAILED #{when_txt} (#{last_action.api_response_message})",
                  left: 'the failed action was never completed',
                  suggest: 'retry it manually or make the player whole',
                  need: 'finish or refund, then confirm in chat'
                ),
                conversation: conversation
              )
            end
            reply = "your #{last_action.action_type} on #{slug_label(action_slug)} hit a snag #{when_txt} and didn't go through - a teammate is finishing it now"
          else
            labels << 'cashier-action-needed'
            safe_telegram do
              Games::TelegramNotifier.human_escalation(
                account: account, contact: contact,
                reason: escalation_context(
                  wants: "status of their #{last_action.action_type} on #{action_slug}",
                  done: "checked records: status is '#{last_action.status}' (#{when_txt})",
                  left: 'unclear whether it completed',
                  suggest: 'verify on the panel and tell the player',
                  need: 'the real outcome of that action'
                ),
                conversation: conversation
              )
            end
            reply = "your last #{last_action.action_type} on #{slug_label(action_slug)} shows '#{last_action.status}' - double-checking with the team now"
          end
        else
          # (d) nothing pending + nothing recent -> ask what they need.
          reply = "you're all clear - no loads or cashouts in flight. what do you need?"
        end
      rescue StandardError => e
        Rails.logger.error("[Orchestrator] Status check failed: #{e.message}")
        labels << 'cashier-action-needed'
        safe_telegram do
          Games::TelegramNotifier.human_escalation(
            account: account, contact: contact,
            reason: escalation_context(
              wants: 'a status update on their recent activity',
              done: "status lookup crashed (#{e.class}: #{e.message})",
              left: 'player still has no answer',
              suggest: 'check their ledger and recent game actions by hand',
              need: 'reply to the player with their real status'
            ),
            conversation: conversation
          )
        end
        reply = 'pulling up your account now - give me one minute'
      end

      { reply: reply, labels: labels.uniq }
    end

    # S1 - newest customer load-ask in the message window that never produced a
    # successful (or in-flight) load. The most recent money ask wins; if that
    # ask already completed, nothing is unresolved (stops the scan). Never raises.
    def unresolved_load_ask_from_window
      return nil unless messages.is_a?(Array)

      customer_msgs = messages.select do |m|
        m.is_a?(Hash) ? (m[:role] || m['role']).to_s == 'user' : (m.respond_to?(:incoming?) && m.incoming?)
      end

      customer_msgs.last(50).reverse_each do |m|
        text = m.is_a?(Hash) ? (m[:content] || m['content']).to_s : m.content.to_s
        det = begin
          Games::IntentDetector.detect(text)
        rescue StandardError
          nil
        end
        next unless det.is_a?(Hash) && det[:intent] == :load

        amt = det[:amount].to_f
        next if amt <= 0

        done = GameAction.where(account_id: account.id, contact_id: contact.id,
                                action_type: 'load', status: %w[success pending], amount: amt)
                         .where('created_at >= ?', 24.hours.ago)
                         .exists?
        return nil if done

        return { amount: amt, game_slug: det[:game_slug] }
      end
      nil
    rescue StandardError => e
      Rails.logger.error("[Orchestrator] unresolved_load_ask_from_window failed: #{e.message}")
      nil
    end

    # S1 - short human phrase for how long ago something happened.
    def time_ago_phrase(time)
      return 'just now' if time.blank?

      secs = (Time.current - time).to_i
      return 'just now' if secs < 60
      return "#{secs / 60} min ago" if secs < 3600
      return "#{secs / 3600}h ago" if secs < 86_400

      "#{secs / 86_400}d ago"
    rescue StandardError
      ''
    end

    # S2 - explicit game wins; otherwise disambiguate from the games the player
    # actually has usernames on. Returns a slug, a question Hash (more than one
    # candidate), or falls back to the normal slug resolution.
    def chosen_game_slug_for_balance(intent)
      explicit = intent.is_a?(Hash) ? intent[:game_slug] : nil
      return explicit if explicit.present?

      stored = (contact.custom_attributes || {}).keys
                                                .select { |k| k.to_s.start_with?('game_username_') }
                                                .map { |k| k.to_s.sub('game_username_', '') }
      stored = stored.select { |s| pick_agent_game(s) }

      return stored.first if stored.size == 1

      if stored.size > 1
        names = stored.map { |s| slug_label(s) }
        return { reply: "which game - #{humanize_list(names)}?", labels: ['balance-check-requested'] }
      end

      chosen_game_slug(intent)
    rescue StandardError
      chosen_game_slug(intent)
    end

    # S2/R3 - state the player's REAL cashout window from the rule layer.
    def cashout_limits_reply(intent)
      slug = chosen_game_slug(intent)
      rules = game_rules_for(slug)
      last_dep = last_deposit_for_cashout(slug)

      # No rule row or no history -> the generic configured-rules reply.
      return handle_cashout_rules(intent) unless rules && last_dep

      if last_dep[:type] == 'freeplay'
        min_c = last_dep[:amount] * (rules.cashout_freeplay_multiplier || 5).to_f
        max_c = (rules.cashout_freeplay_max || 50).to_f
      else
        min_c = last_dep[:amount] * (rules.cashout_min_multiplier || 4).to_f
        max_c = [last_dep[:amount] * (rules.cashout_max_multiplier || 10).to_f, (rules.cashout_max_amount || 250).to_f].min
      end
      min_c = [min_c, (rules.cashout_min_amount || 10).to_f].max

      {
        reply: "on your last $#{fmt_amt(last_dep[:amount])} #{last_dep[:type]}: min cashout $#{fmt_amt(min_c)}, max $#{fmt_amt(max_c)} on #{slug_label(slug)}",
        labels: ['cashout-rules']
      }
    rescue StandardError => e
      Rails.logger.error("[Orchestrator] cashout_limits_reply failed: #{e.message}")
      handle_cashout_rules(intent)
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
          reason: escalation_context(
            wants: "to vent / get a problem fixed: #{(latest_customer_text || '').truncate(100)}",
            done: 'Bella sent a calming reply - the player does NOT know a human was pinged',
            left: 'the underlying problem is unresolved',
            suggest: 'read the last few messages and take over quietly',
            need: 'a human eye on this conversation now'
          ),
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
            reason: escalation_context(
              wants: "help with a tech issue: #{(latest_customer_text || '').truncate(100)}",
              done: "no stored credentials/links could auto-resolve it (game: #{game_slug || 'unknown'})",
              left: 'player still stuck',
              suggest: 'check their login/game on the panel',
              need: 'fix or work around the issue and reply in chat'
            ),
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

    # S2 (June 10) - classify the ask first, then answer with REAL numbers only.
    # Cashout-limit questions -> R3 rule math; load-status questions -> the S1
    # path; otherwise live game balance via the existing client call. An API
    # failure escalates with the full R8 context and NEVER invents a number.
    # No account on the game -> offer signup (existing yes/no create path).
    def handle_balance_check(intent)
      ask = (latest_customer_text || recent_customer_text).to_s.downcase

      # (a) cashout-limit question -> answer from the R3 rule math.
      if ask.match?(/(?:how much|what).{0,30}(?:cash\s*out|withdraw|redeem)|cash\s*out\s+(?:limit|max|min(?:imum)?)|(?:max|min(?:imum)?)(?:imum)?\s+cash\s*out/)
        return cashout_limits_reply(intent)
      end

      # (a) load-status question wearing a balance hat -> S1 path.
      if ask.match?(/went through|did my (?:load|deposit|payment)|status of/)
        return handle_status_check(intent)
      end

      game_slug = chosen_game_slug_for_balance(intent)
      return game_slug if game_slug.is_a?(Hash) # disambiguation question

      unless game_slug
        return { reply: 'which game do you want me to check?', labels: ['balance-check-requested'] }
      end

      begin
        username = find_game_username_for_slug(contact, game_slug)
        unless username
          # (c) no account on this game -> offer to create one; a "yes" lands in
          # the existing pending_transfer_create path (amount 0 = create only).
          store_pending_transfer_create(game_slug, 0)
          return {
            reply: "you don't have a #{slug_label(game_slug)} account with us yet - want me to set one up?",
            labels: ['balance-check-requested', 'needs-account-offer']
          }
        end

        result = execute_game_api(
          game_slug: game_slug,
          action: 'agent_balance',
          username: username
        )

        if result[:success] && result[:balance]
          balance = result[:balance]
          reply = "your #{slug_label(game_slug)} balance is $#{fmt_amt(balance)}"

          begin
            rules = game_rules_for(game_slug)
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
              reason: escalation_context(
                wants: "their #{slug_label(game_slug)} balance",
                done: "live balance call failed (#{result[:error]})",
                left: 'player has no number yet - nothing was guessed',
                suggest: 'check the panel by hand and tell them the exact figure',
                need: "the real #{slug_label(game_slug)} balance for #{username}"
              ),
              conversation: conversation
            )
          end
          {
            reply: "having trouble reaching #{slug_label(game_slug)} right now - a teammate is pulling your exact balance, won't be long.",
            labels: %w[cashier-action-needed balance-check-requested]
          }
        end
      rescue StandardError => e
        Rails.logger.error("[Orchestrator] Balance check failed: #{e.message}")
        safe_telegram do
          Games::TelegramNotifier.human_escalation(
            account: account, contact: contact,
            reason: escalation_context(
              wants: "their #{slug_label(game_slug)} balance",
              done: "balance lookup crashed (#{e.class}: #{e.message})",
              left: 'player has no number yet - nothing was guessed',
              suggest: 'check the panel by hand and tell them the exact figure',
              need: "the real #{slug_label(game_slug)} balance"
            ),
            conversation: conversation
          )
        end
        {
          reply: "having trouble pulling that up - a teammate is grabbing your exact balance now.",
          labels: %w[cashier-action-needed balance-check-requested]
        }
      end
    end

    # Transfer requests do NOT arrive structured — the :transfer_between_games intent
    # only carries game_slug. We extract {source_slug, targets:[{slug, amount}]} from the
    # message. Primary path: the shared Ai::DeepseekClient (reasoning_content→content→nil).
    # Fallback: regex + IntentDetector. Both feed one normalizer.
    TRANSFER_PLAN_SYSTEM_PROMPT = <<~'PROMPT'
      You convert a customer's game-transfer request into JSON. The customer wants to cash out from ONE source game and load the proceeds onto one or more target games.
      Respond with ONLY valid compact JSON, no markdown, no commentary:
      {"source_game":"<name>","cashout_amount":<number>,"loads":[{"game":"<name>","amount":<number>}]}
      Amounts are plain numbers, no dollar sign. If the source game or amount is not stated, use null. Copy game names exactly as the customer wrote them. Never invent loads.
    PROMPT

    def handle_transfer_between_games(intent)
      # R1 (June 10) - transfer_mode 'off' declines before any parsing or panel calls.
      if transfer_mode_pref == 'off'
        return { reply: "we don't do game-to-game transfers right now - you can cash out or keep playing, your call.", labels: ['transfer-off'] }
      end

      text = (latest_customer_text || recent_customer_text).to_s
      plan = extract_transfer_plan(text)

      return escalate_transfer_unclear(plan) if plan.nil? || plan[:source_slug].blank?

      source_slug = plan[:source_slug]

      # Reject source == target.
      raw_targets = Array(plan[:loads])
      targets = raw_targets.reject { |t| t[:game_slug].present? && t[:game_slug] == source_slug }
      if targets.empty? && raw_targets.any?
        return { reply: "can't transfer a game onto itself — which other game do you want it on?", labels: ['transfer-same-game'] }
      end
      if targets.empty?
        return { reply: 'which games do you want me to move it to, and how much on each?', labels: ['transfer-needs-targets'] }
      end

      source_ag = pick_agent_game(source_slug)
      return { reply: unavailable_game_reply(source_slug), labels: ['game-unavailable'] } unless source_ag

      source_username = find_game_username_for_slug(contact, source_slug)
      unless source_username
        # R1 - no username on the source game means they never played it here.
        return { reply: "looks like you haven't played #{source_ag.game.name} with us yet - nothing there to move.", labels: ['transfer-no-source-account'] }
      end

      # Feature 3 — velocity guard also gates the transfer's cashout step.
      vel = cashout_velocity_state
      if vel[:exceeded]
        safe_telegram do
          Games::TelegramNotifier.human_escalation(
            account: account, contact: contact,
            reason: escalation_context(
              wants: 'a game-to-game transfer (cashout leg)',
              done: "VELOCITY FLAG: #{vel[:count]} successful cashouts in #{vel[:hours]}h (threshold #{vel[:threshold]}) - transfer HELD, nothing moved",
              left: 'the held transfer',
              suggest: 'eyeball the pattern before releasing',
              need: 'clear or decline this transfer'
            ),
            conversation: conversation
          )
        end
        return { reply: 'let me have a teammate check this one.', labels: ['velocity-flag', 'needs-human'] }
      end

      # STEP 2 — read the source-game balance.
      source_executor = Games::ActionExecutor.new(agent_game: source_ag, contact: contact, conversation: conversation)
      balance =
        begin
          source_executor.check_player_balance(game_username: source_username)
        rescue StandardError => e
          Rails.logger.error("[Orchestrator] transfer balance read failed: #{e.message}")
          nil
        end

      if balance.nil?
        safe_telegram do
          Games::TelegramNotifier.human_escalation(
            account: account, contact: contact,
            reason: escalation_context(
              wants: 'a game-to-game transfer',
              done: "balance read FAILED for #{source_username} on #{source_ag.game.name} - NOTHING moved",
              left: 'the whole transfer',
              suggest: 'check the panel and run the transfer manually if the balance is there',
              need: "the real #{source_ag.game.name} balance, then move the money or decline"
            ),
            conversation: conversation
          )
        end
        return { reply: "let me double-check your #{source_ag.game.name} balance — one sec", labels: %w[cashier-action-needed transfer] }
      end

      balance = balance.to_f
      if balance <= 0
        return { reply: "looks like your #{source_ag.game.name} balance is empty — nothing to move right now.", labels: ['transfer-empty'] }
      end

      requested_total = targets.sum { |t| t[:amount].to_f }

      # R1 (June 10) - the transfer_mode decides the moveable cap:
      #   whole        -> full current balance
      #   deposit_only -> most recent real deposit, capped by current balance
      #   off          -> declined at the top of the handler
      # Requested more than moveable -> move NOTHING, state the real numbers.
      # The transfer itself stays a normal cashout + normal load; the velocity,
      # dedup, approval-gate and credential-cap guards still apply on both legs.
      mode = transfer_mode_pref
      if mode == 'deposit_only'
        deposit_amount = original_deposit_on_source(source_slug)
        if deposit_amount <= 0
          return { reply: "i don't see a deposit on #{source_ag.game.name} to move - a teammate will take a look.", labels: %w[cashier-action-needed transfer] }
        end
        # MONEY-SAFETY CAP: never move more than the current balance, ever.
        moveable = [deposit_amount, balance].min
        fork = 'deposit_only'
      else
        moveable = balance
        fork = 'whole_balance'
      end

      if requested_total <= 0
        return { reply: "how much do you want to move off #{source_ag.game.name}?", labels: ['transfer-needs-amount'] }
      end

      if requested_total > moveable + 0.001
        reply = if fork == 'deposit_only'
                  "you've got $#{fmt_amt(balance)} on #{source_ag.game.name} and your last deposit was $#{fmt_amt(deposit_amount)} - i can move up to $#{fmt_amt(moveable)}, that's short of the $#{fmt_amt(requested_total)} you wanted."
                else
                  "you've got $#{fmt_amt(balance)} on #{source_ag.game.name}, that's short of the $#{fmt_amt(requested_total)} you wanted to load."
                end
        return { reply: reply, labels: ['transfer-short'] }
      end

      source_amount = requested_total

      # Dedup guard (Finding-2): a rapid identical cashout (same game + amount) within the
      # window is a double-send — skip BOTH the cashout AND the downstream load.
      if recent_cashout_duplicate?(agent_game: source_ag, amount: source_amount)
        Rails.logger.info("[Orchestrator] transfer DEDUP: $#{fmt_amt(source_amount)} on #{source_ag.game.name} within #{CASHOUT_DEDUP_WINDOW_SECONDS}s — skipping duplicate")
        return { reply: "already processing your $#{fmt_amt(source_amount)} transfer — hang tight!", labels: ['transfer-duplicate-skipped', 'needs-human'] }
      end

      # STEP 1 — cash out source_amount from the source game. CHECK success.
      cashout_result = source_executor.cashout_player(
        game_username: source_username,
        amount: source_amount,
        metadata: { source: 'bella_transfer', fork: fork, conversation_id: conversation&.id }
      )
      record_api_result(source_ag, cashout_result)

      unless cashout_result[:ok]
        # approval_required lands here too — move no money, escalate.
        safe_telegram { Games::TelegramNotifier.load_failed(cashout_result[:action]) if cashout_result[:action] }
        safe_telegram do
          Games::TelegramNotifier.human_escalation(
            account: account, contact: contact,
            reason: escalation_context(
              wants: "transfer $#{fmt_amt(source_amount)} off #{source_ag.game.name}",
              done: "cashout leg FAILED (#{cashout_result[:error]}, code #{cashout_result[:code]}) - NO money moved",
              left: 'the whole transfer',
              suggest: 'run it manually once the panel cooperates',
              need: "move $#{fmt_amt(source_amount)} for #{source_username} or tell the player it is off"
            ),
            conversation: conversation
          )
        end
        reply = cashout_result[:code].to_s == 'approval_required' ? "your transfer needs a quick review — a teammate's on it." : "hit a snag cashing out from #{source_ag.game.name} — flagged a teammate, they'll sort your transfer in a couple minutes."
        return { reply: reply, labels: ['transfer-failed', 'needs-human'] }
      end

      # STEPS 4-5 — distribute source_amount across targets in order; count only successes.
      funds = source_amount
      loaded = []
      failed = []
      pending_create = nil

      targets.each do |t|
        want = t[:amount].to_f
        load_amt = want > 0 ? [want, funds].min : funds
        next if load_amt <= 0

        target_slug = t[:game_slug]
        label = target_slug.present? ? slug_label(target_slug) : (t[:game_text].presence || 'unknown game')
        target_ag = target_slug.present? ? pick_agent_game(target_slug) : nil

        unless target_ag
          failed << { label: label, amount: load_amt, reason: 'game unavailable' }
          next
        end

        target_username = find_game_username_for_slug(contact, target_slug)
        if target_username.blank?
          # STEP 4 — no account on target: do NOT auto-create silently. Remember the
          # first one; the yes/no handler offers setup on the player's next message.
          pending_create ||= { slug: target_slug, amount: load_amt }
          failed << { label: target_ag.game.name, amount: load_amt, reason: 'no account (pending setup)' }
          next
        end

        target_executor = Games::ActionExecutor.new(agent_game: target_ag, contact: contact, conversation: conversation)
        load_result = target_executor.load_player(
          game_username: target_username,
          amount: load_amt,
          metadata: { source: 'bella_transfer', conversation_id: conversation&.id }
        )
        record_api_result(target_ag, load_result)

        if load_result[:ok]
          loaded << { label: target_ag.game.name, amount: load_amt }
          funds -= load_amt
        else
          failed << { label: target_ag.game.name, amount: load_amt, reason: "#{load_result[:error]} (code #{load_result[:code]})" }
        end
      end

      loaded_total = loaded.sum { |x| x[:amount] }
      remaining = source_amount - loaded_total

      store_pending_transfer_create(pending_create[:slug], pending_create[:amount]) if pending_create

      # STEP 5 - ALWAYS report the real state to Telegram. Half-fails (cashout OK,
      # load failed) use the R8 full-context format so the human sees the whole
      # situation at a glance; clean completions keep the compact one-liner.
      if failed.any?
        loaded_txt = loaded.any? ? "; loaded #{loaded.map { |x| "$#{fmt_amt(x[:amount])} #{x[:label]} OK" }.join(', ')}" : ''
        report = escalation_context(
          wants: "move $#{fmt_amt(requested_total)} off #{source_ag.game.name}",
          done: "cashed out $#{fmt_amt(source_amount)} from #{source_ag.game.name} (#{fork})#{loaded_txt}",
          left: "FAILED: #{failed.map { |x| "$#{fmt_amt(x[:amount])} #{x[:label]} (#{x[:reason]})" }.join(', ')}. Remaining: $#{fmt_amt(remaining)} cashed out and NOT loaded - money is safe, not lost",
          suggest: 'asked the player: load it on another game, or take the money?',
          need: 'finish the failed load or pay the player out, then confirm in chat'
        )
      else
        report = "TRANSFER (#{fork}) - Cashed out $#{fmt_amt(source_amount)} from #{source_ag.game.name}."
        report += " Loaded: #{loaded.map { |x| "$#{fmt_amt(x[:amount])} #{x[:label]} OK" }.join(', ')}." if loaded.any?
        report += if remaining > 0.001
                    " Remaining: $#{fmt_amt(remaining)} - cashed out, tell player to request it."
                  else
                    ' Remaining: $0 - fully loaded.'
                  end
      end
      safe_telegram do
        Games::TelegramNotifier.human_escalation(account: account, contact: contact, reason: report, conversation: conversation)
      end

      # STEP 7 — tell the customer what actually happened.
      build_transfer_reply(source_ag, source_amount, loaded, failed, remaining, pending_create)
    end

    def build_transfer_reply(source_ag, source_amount, loaded, failed, remaining, pending_create)
      loaded_phrase = loaded.map { |x| "$#{fmt_amt(x[:amount])} on #{x[:label]}" }.join(', ')

      if loaded.empty? && pending_create
        return { reply: "you're not on #{slug_label(pending_create[:slug])} yet — want me to set you up? (your $#{fmt_amt(pending_create[:amount])} is ready to go)", labels: ['transfer-needs-create', 'needs-human'] }
      end

      if loaded.any? && failed.empty? && remaining <= 0.001
        return { reply: "done! cashed out $#{fmt_amt(source_amount)} from #{source_ag.game.name} and loaded #{loaded_phrase}.", labels: ['transfer-complete'] }
      end

      if loaded.any?
        reply = "cashed out $#{fmt_amt(source_amount)} from #{source_ag.game.name} and loaded #{loaded_phrase}."
        if pending_create
          reply += " you're not on #{slug_label(pending_create[:slug])} yet — want me to set you up?"
        elsif failed.any?
          # R1 half-fail - the cashed-out money is never lost: offer the choice.
          reply += " couldn't get #{failed.map { |x| "$#{fmt_amt(x[:amount])} on #{x[:label]}" }.join(', ')} through - your money's safe."
          reply += " want me to load it on another game, or take the money?" if remaining > 0.001
        end
        labels = (failed.any? || pending_create) ? ['transfer-partial', 'needs-human'] : ['transfer-complete']
        return { reply: reply, labels: labels }
      end

      # R1 half-fail - cashout landed, no load did. Money is safe; offer the choice.
      { reply: "cashed out $#{fmt_amt(source_amount)} from #{source_ag.game.name} but couldn't load it just now - your money's safe. want me to load it on another game, or take the money?", labels: ['transfer-failed', 'needs-human'] }
    end

    def escalate_transfer_unclear(_plan)
      safe_telegram do
        Games::TelegramNotifier.human_escalation(
          account: account, contact: contact,
          reason: escalation_context(
            wants: "a transfer Bella couldn't parse: #{(latest_customer_text || recent_customer_text).to_s.truncate(160)}",
            done: 'asked the player to clarify source/amount/targets - nothing moved',
            left: 'the transfer, if it was one',
            suggest: 'read the conversation and take it manually if urgent',
            need: 'nothing yet unless the player stays stuck'
          ),
          conversation: conversation
        )
      end
      { reply: 'want to make sure i get this right — which game am i cashing out from, how much, and which games should it go to?', labels: ['transfer-unclear', 'needs-human'] }
    end

    def extract_transfer_plan(text)
      return nil if text.blank?
      extract_transfer_plan_via_llm(text) || extract_transfer_plan_via_regex(text)
    end

    # Primary extractor — shared DeepSeek client (reasoning_content→content→nil).
    def extract_transfer_plan_via_llm(text)
      return nil unless defined?(Ai::DeepseekClient)

      raw = Ai::DeepseekClient.complete(
        system_prompt: TRANSFER_PLAN_SYSTEM_PROMPT,
        user_content: text.to_s,
        max_tokens: 512,
        temperature: 0
      )
      return nil if raw.blank?

      json = raw.to_s.sub(/\A```(?:json)?\s*/i, '').sub(/\s*```\z/, '').strip
      # reasoning_content may wrap JSON in prose — grab the first {...} block.
      if (brace = json.match(/\{.*\}/m))
        json = brace[0]
      end
      normalize_transfer_plan(JSON.parse(json))
    rescue StandardError => e
      Rails.logger.warn("[Orchestrator] transfer DeepSeek extract failed: #{e.class}: #{e.message}")
      nil
    end

    def normalize_transfer_plan(data)
      return nil unless data.is_a?(Hash)
      data = data.stringify_keys

      src_text = data['source_game'].to_s
      source_slug = src_text.present? ? Games::IntentDetector.detect_game(src_text) : nil
      cashout = parse_amount(data['cashout_amount'])

      loads = Array(data['loads']).filter_map do |l|
        next unless l.is_a?(Hash)
        l = l.stringify_keys
        amt = parse_amount(l['amount'])
        g_text = l['game'].to_s
        { game_text: g_text, game_slug: g_text.present? ? Games::IntentDetector.detect_game(g_text) : nil, amount: amt }
      end

      return nil if source_slug.blank? && cashout.nil? && loads.empty?
      { source_text: src_text, source_slug: source_slug, cashout_amount: cashout, loads: loads }
    end

    def extract_transfer_plan_via_regex(text)
      str = text.to_s
      source_slug = nil
      source_text = nil
      cashout = nil
      if (m = str.match(/(?:cash\s*out|cashout|redeem|withdraw|transfer|move)\s+\$?(\d+(?:\.\d{1,2})?)\s+(?:from|off|out of|outta|on)\s+([a-z0-9 _]+?)(?:,|;|\band\b|\bload\b|\bto\b|\bonto\b|$)/i))
        cashout = m[1].to_f
        source_text = m[2].strip
        source_slug = Games::IntentDetector.detect_game(source_text)
      end

      loads = []
      section = nil
      if (idx = (str =~ /\bload\b/i))
        section = str[idx..]
      elsif (idx2 = (str =~ /\b(?:to|onto)\b/i))
        section = str[idx2..]
      end
      if section
        section = section.sub(/\A(?:load|onto|to)\b/i, '')
        section.split(/,|;|\band\b/i).each do |seg|
          sm = seg.match(/\$?(\d+(?:\.\d{1,2})?)\s+([a-z0-9 _]+)/i)
          next unless sm
          amt = sm[1].to_f
          next if amt <= 0
          g_text = sm[2].strip
          loads << { game_text: g_text, game_slug: Games::IntentDetector.detect_game(g_text), amount: amt }
        end
      end

      return nil if source_slug.blank? && cashout.nil? && loads.empty?
      { source_text: source_text, source_slug: source_slug, cashout_amount: cashout, loads: loads }
    end

    # ---- transfer / fraud / failover shared helpers ----

    def reply_pref_cached
      @reply_pref_cached ||= begin
        ReplyPreference.for_account(account.id)
      rescue StandardError
        nil
      end
    end

    # Finding-2 dedup: true if an identical cashout (same contact + agent_game + amount,
    # status pending/success) was recorded within CASHOUT_DEDUP_WINDOW_SECONDS. FAIL-OPEN:
    # on a query error return false (proceed with the normal cashout) rather than block a
    # legitimate payout — the velocity guard + Telegram escalation still backstop a true
    # double, and wrongly blocking a real cashout is worse UX. The error is logged loudly.
    def recent_cashout_duplicate?(agent_game:, amount:)
      GameAction.where(account_id: account.id, contact_id: contact.id,
                       agent_game_id: agent_game.id, action_type: 'cashout',
                       status: %w[pending success], amount: amount)
                .where('created_at >= ?', CASHOUT_DEDUP_WINDOW_SECONDS.seconds.ago)
                .exists?
    rescue StandardError => e
      Rails.logger.error("[Orchestrator] recent_cashout_duplicate? FAILED — failing open (proceeding): #{e.class}: #{e.message}")
      false
    end

    # R1 (June 10) - modes: 'off' | 'deposit_only' | 'whole'. Read order:
    # reply_preferences.transfer_mode -> account.custom_attributes['transfer_mode']
    # -> 'deposit_only' (operator-confirmed default). Existing rows that carry the
    # old column default 'whole' keep whole-balance transfers (see log D2).
    def transfer_mode_pref
      pref = reply_pref_cached
      v = pref.respond_to?(:transfer_mode) ? pref.transfer_mode.to_s.strip.downcase : ''
      return v if %w[off deposit_only whole].include?(v)
      ca = (account.custom_attributes || {})['transfer_mode'].to_s.strip.downcase
      return ca if %w[off deposit_only whole].include?(ca)
      'deposit_only'
    rescue StandardError
      'deposit_only'
    end

    def transfer_deposit_shortfall_mode
      pref = reply_pref_cached
      return 'transfer_available' unless pref.respond_to?(:transfer_deposit_shortfall_mode)
      (pref.transfer_deposit_shortfall_mode.presence || 'transfer_available').to_s
    rescue StandardError
      'transfer_available'
    end

    def game_rules_for(slug)
      game = Game.find_by(slug: slug)
      game ? GameRule.find_by(account_id: account.id, game_id: game.id) : nil
    rescue StandardError
      nil
    end

    # deposit_only fork — the player's most recent real (non-freeplay) deposit on the
    # source game. NOT their winnings.
    def original_deposit_on_source(slug)
      game_actions_for_slug(contact.id, slug)
        .where(action_type: 'load', status: 'success')
        .where("COALESCE(metadata->>'freeplay', 'false') != 'true'")
        .order(created_at: :desc)
        .limit(1)
        .pluck(:amount)
        .first.to_f
    rescue StandardError => e
      Rails.logger.error("[Orchestrator] original_deposit_on_source failed: #{e.message}")
      0.0
    end

    # R3 - the player's most recent successful load on the game, with its type.
    # Type: 'freeplay' | 'bonus' | 'referral' | 'deposit'. A keep-in from a
    # partial cashout (R5) counts as a deposit - it drives the next cashout's
    # rules on purpose. Never raises; nil means no load history.
    def last_deposit_for_cashout(slug)
      action = game_actions_for_slug(contact.id, slug)
               .where(action_type: 'load', status: 'success')
               .order(created_at: :desc)
               .first
      return nil unless action && action.amount.to_f > 0

      md = action.metadata.is_a?(Hash) ? action.metadata : {}
      type = if md['freeplay'].to_s == 'true'
               'freeplay'
             elsif md['deposit_bonus'].to_s == 'true'
               'bonus'
             elsif md['referral'].to_s == 'true'
               'referral'
             else
               'deposit'
             end
      { amount: action.amount.to_f, type: type }
    rescue StandardError => e
      Rails.logger.error("[Orchestrator] last_deposit_for_cashout failed: #{e.message}")
      nil
    end

    # R4 + MEGA2 P3 - over-max cashout behavior is an operator SETTING
    # (cashout_overmax_mode). 'cash_whole' (DEFAULT, today's behavior): the
    # payout stays cashier-manual, Bella moves no money and states the math
    # plainly - the over-max remainder does not carry, never silently.
    # 'pay_max_recharge': Bella runs the IN-GAME legs herself (redeem the
    # requested amount, recharge the over-max remainder back to the SAME
    # game/user); the external payout of the max stays cashier-manual. A
    # failed recharge leg escalates with the REAL state and is NEVER
    # auto-retried. 'ask_first': move NO money - ask the player which they
    # want, hold the choice on the conversation, escalate; no reply ->
    # nothing moves (flag stales out after 30 min).
    def handle_over_max_cashout(game_slug, requested_amount, max_cashout, last_dep)
      case cashout_overmax_mode_pref
      when 'pay_max_recharge'
        overmax_pay_max_recharge(game_slug, requested_amount, max_cashout, last_dep)
      when 'ask_first'
        overmax_ask_first(game_slug, requested_amount, max_cashout, last_dep)
      else
        overmax_cash_whole(game_slug, requested_amount, max_cashout, last_dep)
      end
    end

    # Today's default: no panel calls, cashier-manual payout, plain math.
    def overmax_cash_whole(game_slug, requested_amount, max_cashout, last_dep)
      leftover = requested_amount - max_cashout
      dep_txt = last_dep ? "your last $#{fmt_amt(last_dep[:amount])} #{last_dep[:type]}" : 'your deposits'
      safe_telegram do
        Games::TelegramNotifier.human_escalation(
          account: account, contact: contact,
          reason: escalation_context(
            wants: "cash out $#{fmt_amt(requested_amount)} on #{game_slug} (over the $#{fmt_amt(max_cashout)} max, mode cash_whole)",
            done: "nothing executed yet - player told plainly: $#{fmt_amt(max_cashout)} paid, the $#{fmt_amt(leftover)} over max does not carry",
            left: 'the payout itself',
            suggest: "cash out the whole balance, pay $#{fmt_amt(max_cashout)} - the over-limit does not carry",
            need: "send $#{fmt_amt(max_cashout)} to #{contact.name} and confirm in chat"
          ),
          conversation: conversation
        )
      end
      {
        reply: "max cashout on #{dep_txt} is $#{fmt_amt(max_cashout)} - you'll get $#{fmt_amt(max_cashout)}, the $#{fmt_amt(leftover)} over the max doesn't carry.",
        labels: %w[cashout-over-max cashier-action-needed]
      }
    end

    # pay_max_recharge: redeem leg + recharge leg in-game; payout cashier-manual.
    # Money rules: every leg [:ok]-checked, recharge idempotent (deterministic
    # order_id on the redeem action), failures escalate with the real state.
    def overmax_pay_max_recharge(game_slug, requested_amount, max_cashout, last_dep)
      leftover = (requested_amount - max_cashout).round(2)
      ag = pick_agent_game(game_slug)
      username = ag ? find_game_username_for_slug(contact, game_slug) : nil

      if ag.nil? || username.blank?
        safe_telegram do
          Games::TelegramNotifier.human_escalation(
            account: account, contact: contact,
            reason: escalation_context(
              wants: "cash out $#{fmt_amt(requested_amount)} on #{game_slug} (over max $#{fmt_amt(max_cashout)}, mode pay_max_recharge)",
              done: "NOTHING moved - #{ag.nil? ? 'game unavailable' : 'no stored username'}, the redeem/recharge legs cannot run",
              left: "redeem $#{fmt_amt(requested_amount)}, recharge $#{fmt_amt(leftover)} back, pay $#{fmt_amt(max_cashout)}",
              suggest: 'run all legs manually on the panel',
              need: "the full over-max flow for #{contact.name}, then confirm in chat"
            ),
            conversation: conversation
          )
        end
        return { reply: "your cashout needs a quick teammate touch - they'll send your $#{fmt_amt(max_cashout)} shortly.", labels: %w[cashout-over-max needs-human] }
      end

      if recent_cashout_duplicate?(agent_game: ag, amount: requested_amount)
        Rails.logger.info("[Orchestrator] overmax DEDUP: $#{fmt_amt(requested_amount)} on #{ag.game.name} within #{CASHOUT_DEDUP_WINDOW_SECONDS}s - skipping duplicate")
        return { reply: "already processing your $#{fmt_amt(requested_amount)} cashout - hang tight!", labels: %w[cashout-over-max duplicate-skipped] }
      end

      executor = Games::ActionExecutor.new(agent_game: ag, contact: contact, conversation: conversation)
      redeem = executor.cashout_player(
        game_username: username,
        amount: requested_amount,
        metadata: { source: 'bella_overmax_redeem', overmax_mode: 'pay_max_recharge', conversation_id: conversation&.id }
      )
      record_api_result(ag, redeem)

      unless redeem[:ok]
        safe_telegram { Games::TelegramNotifier.load_failed(redeem[:action]) if redeem[:action] }
        safe_telegram do
          Games::TelegramNotifier.human_escalation(
            account: account, contact: contact,
            reason: escalation_context(
              wants: "cash out $#{fmt_amt(requested_amount)} on #{game_slug} (over max $#{fmt_amt(max_cashout)}, mode pay_max_recharge)",
              done: "redeem leg FAILED (#{redeem[:error]}, code #{redeem[:code]}) - NO money moved",
              left: 'the whole over-max flow',
              suggest: 'run it manually once the panel cooperates',
              need: "redeem $#{fmt_amt(requested_amount)}, recharge $#{fmt_amt(leftover)} back, pay $#{fmt_amt(max_cashout)} to #{contact.name}"
            ),
            conversation: conversation
          )
        end
        reply = redeem[:code].to_s == 'approval_required' ? "your cashout needs a quick review - a teammate's on it." : 'hit a snag on your cashout - flagged a teammate, they will sort it in a couple minutes.'
        return { reply: reply, labels: %w[cashout-over-max cashout-failed needs-human] }
      end

      redeem_action_id = redeem[:action]&.id
      recharge = begin
        executor.load_player(
          game_username: username,
          amount: leftover,
          metadata: { source: 'bella_overmax_recharge', overmax_mode: 'pay_max_recharge',
                      cashout_action_id: redeem_action_id, conversation_id: conversation&.id },
          order_id: "ovmx_#{redeem_action_id || SecureRandom.hex(6)}"
        )
      rescue Games::ActionExecutor::IdempotencyError, ActiveRecord::RecordNotUnique
        { ok: true, already: true }
      end
      record_api_result(ag, recharge) unless recharge[:already]

      if recharge[:ok]
        safe_telegram do
          Games::TelegramNotifier.human_escalation(
            account: account, contact: contact,
            reason: escalation_context(
              wants: "cash out $#{fmt_amt(requested_amount)} on #{game_slug} (over max $#{fmt_amt(max_cashout)}, mode pay_max_recharge)",
              done: "redeemed $#{fmt_amt(requested_amount)} and recharged $#{fmt_amt(leftover)} back to #{username} - in-game legs DONE",
              left: "the external payout of $#{fmt_amt(max_cashout)}",
              suggest: 'send the max to the player now',
              need: "send $#{fmt_amt(max_cashout)} to #{contact.name} and confirm in chat"
            ),
            conversation: conversation
          )
        end
        { reply: "you'll get $#{fmt_amt(max_cashout)} - i put the $#{fmt_amt(leftover)} over the max back on #{slug_label(game_slug)} for you.", labels: %w[cashout-over-max cashier-action-needed] }
      else
        safe_telegram { Games::TelegramNotifier.load_failed(recharge[:action]) if recharge[:action] }
        safe_telegram do
          Games::TelegramNotifier.human_escalation(
            account: account, contact: contact,
            reason: escalation_context(
              wants: "cash out $#{fmt_amt(requested_amount)} on #{game_slug} (over max $#{fmt_amt(max_cashout)}, mode pay_max_recharge)",
              done: "redeemed $#{fmt_amt(requested_amount)} OK; recharge of $#{fmt_amt(leftover)} back to #{username} FAILED (#{recharge[:error]}, code #{recharge[:code]}) - NOT auto-retried",
              left: "$#{fmt_amt(leftover)} is out of the game and NOT recharged; player is owed the $#{fmt_amt(max_cashout)} payout",
              suggest: 'recharge the remainder manually on the panel, then pay the max',
              need: "recharge $#{fmt_amt(leftover)} to #{username} and send $#{fmt_amt(max_cashout)} to #{contact.name}"
            ),
            conversation: conversation
          )
        end
        { reply: "you'll get $#{fmt_amt(max_cashout)} - a teammate is finishing up the part that stays in your game.", labels: %w[cashout-over-max needs-human] }
      end
    end

    # ask_first: move NO money; hold the choice on the conversation. Re-asking
    # while a choice is already pending never re-escalates (idempotent).
    def overmax_ask_first(game_slug, requested_amount, max_cashout, last_dep)
      leftover = requested_amount - max_cashout
      if conversation.blank?
        Rails.logger.warn('[Orchestrator] overmax ask_first: no conversation to hold the choice - falling back to cash_whole')
        return overmax_cash_whole(game_slug, requested_amount, max_cashout, last_dep)
      end

      already_pending = conversation.additional_attributes&.dig('pending_overmax_choice').present?
      unless already_pending
        attrs = (conversation.additional_attributes || {}).merge(
          'pending_overmax_choice' => { 'game_slug' => game_slug, 'requested' => requested_amount.to_f,
                                        'max' => max_cashout.to_f, 'set_at' => Time.current.iso8601 }
        )
        conversation.update_columns(additional_attributes: attrs)
        safe_telegram do
          Games::TelegramNotifier.human_escalation(
            account: account, contact: contact,
            reason: escalation_context(
              wants: "cash out $#{fmt_amt(requested_amount)} on #{game_slug} (over the $#{fmt_amt(max_cashout)} max, mode ask_first)",
              done: "NO money moved - asked the player: keep the $#{fmt_amt(leftover)} in the game, or take $#{fmt_amt(max_cashout)} and drop it",
              left: 'waiting on the player choice; their answer routes the flow',
              suggest: 'nothing yet - hold until they answer',
              need: 'the payout itself once the player picks (Bella will re-escalate)'
            ),
            conversation: conversation
          )
        end
      end
      {
        reply: "max i can send on this one is $#{fmt_amt(max_cashout)}. want the extra $#{fmt_amt(leftover)} left in your game, or just take the $#{fmt_amt(max_cashout)} and drop it?",
        labels: %w[cashout-over-max overmax-choice-pending]
      }
    end

    def clear_pending_overmax_choice
      return if conversation.blank?

      attrs = (conversation.additional_attributes || {}).dup
      attrs.delete('pending_overmax_choice')
      conversation.update_columns(additional_attributes: attrs)
    rescue StandardError => e
      Rails.logger.error("[Orchestrator] clear_pending_overmax_choice failed: #{e.message}")
    end

    # Returns a response hash when the player's answer resolves the over-max
    # choice, nil to fall through (no answer -> nothing moves). Stale (>30 min)
    # or malformed flags are cleared. Ambiguous answers (both options matched)
    # fall through and the player gets re-asked by the normal path.
    def resolve_pending_overmax_choice(answer_text, pending)
      pending = pending.is_a?(Hash) ? pending.stringify_keys : {}
      slug = pending['game_slug']
      requested = pending['requested'].to_f
      max_c = pending['max'].to_f
      set_at = pending['set_at']
      fresh = set_at.blank? || begin
        Time.parse(set_at) > 30.minutes.ago
      rescue StandardError
        true
      end
      unless fresh && slug.present? && requested.positive? && max_c.positive? && requested > max_c
        clear_pending_overmax_choice
        return nil
      end

      answer = answer_text.to_s.downcase
      wants_recharge = answer.match?(/\b(keep|leave|recharge|stay)\b/) || answer.match?(/back (in|on)\b/)
      wants_drop = answer.match?(/\b(drop|take|forget|skip)\b/) || answer.match?(/just (send|the|take)\b/)
      return nil unless wants_recharge ^ wants_drop

      clear_pending_overmax_choice
      last_dep = last_deposit_for_cashout(slug)
      if wants_recharge
        overmax_pay_max_recharge(slug, requested, max_c, last_dep)
      else
        overmax_cash_whole(slug, requested, max_c, last_dep)
      end
    rescue StandardError => e
      Rails.logger.error("[Orchestrator] resolve_pending_overmax_choice failed: #{e.message}")
      nil
    end

    # R4 + MEGA2 P3 - 'cash_whole' | 'pay_max_recharge' | 'ask_first'. Read
    # order: reply_preferences column (when it exists) ->
    # account.custom_attributes['cashout_overmax_mode'] -> 'cash_whole'
    # (operator-confirmed default). Unknown non-blank values warn-log and fall
    # back to cash_whole. No migration required.
    OVERMAX_MODES = %w[cash_whole pay_max_recharge ask_first].freeze

    def cashout_overmax_mode_pref
      pref = reply_pref_cached
      if pref.respond_to?(:cashout_overmax_mode)
        v = pref.cashout_overmax_mode.to_s.strip.downcase
        return v if OVERMAX_MODES.include?(v)
        Rails.logger.warn("[Orchestrator] unknown cashout_overmax_mode #{v.inspect} on reply_preferences - treating as cash_whole") if v.present?
      end
      ca = (account.custom_attributes || {})['cashout_overmax_mode'].to_s.strip.downcase
      return ca if OVERMAX_MODES.include?(ca)
      Rails.logger.warn("[Orchestrator] unknown cashout_overmax_mode #{ca.inspect} on account custom_attributes - treating as cash_whole") if ca.present?
      'cash_whole'
    rescue StandardError
      'cash_whole'
    end

    # R7 (June 10) - dollar gate on the automated payment->load path.
    # Read order: reply_preferences.auto_load_threshold (when the column exists)
    # -> account.custom_attributes['auto_load_threshold'] -> 200. NOTE: distinct
    # from the email-confidence 'auto_load_threshold' inside payment_scoring_config
    # (a 0-100 score) - this one is dollars.
    def auto_load_threshold_pref
      pref = reply_pref_cached
      if pref.respond_to?(:auto_load_threshold)
        v = pref.auto_load_threshold
        return v.to_f if v.present? && v.to_f > 0
      end
      ca = (account.custom_attributes || {})['auto_load_threshold']
      return ca.to_f if ca.present? && ca.to_f > 0
      200.0
    rescue StandardError
      200.0
    end

    # R7 - verified deposit above the threshold: do NOT load. Creates a pending
    # ApprovalRequest (action_type 'load' - the F15 record type; loads stay
    # manual-execute on approval, AutoResume only auto-executes cashouts),
    # Telegrams the full R8 context, returns the hold response.
    # Returns nil when the amount is within the threshold.
    def over_threshold_load_hold(payment, game_name)
      amt = payment.is_a?(Hash) ? payment[:amount].to_f : 0.0
      threshold = auto_load_threshold_pref
      return nil unless amt > threshold

      hold_approval = nil
      begin
        hold_approval = ApprovalRequest.where(account_id: account.id, action_type: 'load', status: 'pending')
                                       .where("metadata->>'payment_id' = ?", payment[:id].to_s)
                                       .first
        hold_approval ||= ApprovalRequest.create!(
          account: account,
          requesting_user: account.account_users.first&.user,
          action_type: 'load',
          target_type: 'Contact',
          target_id: contact&.id,
          amount: amt,
          status: 'pending',
          metadata: { 'payment_id' => payment[:id].to_s, 'game_name' => game_name.to_s,
                      'source' => 'bella_over_threshold' }
        )
      rescue StandardError => e
        Rails.logger.error("[Orchestrator] over-threshold approval create failed: #{e.message}")
      end

      safe_telegram do
        Games::TelegramNotifier.human_escalation(
          account: account, contact: contact,
          reason: escalation_context(
            wants: "load a verified $#{fmt_amt(amt)} deposit on #{game_name}",
            done: "payment verified (id #{payment[:id]}) - NOT loaded, over the $#{fmt_amt(threshold)} auto-load threshold",
            left: 'the load itself',
            suggest: 'approve and load it manually if the payment looks right',
            need: "approve the $#{fmt_amt(amt)} load#{hold_approval ? approval_ref_text(hold_approval) : ' (pending approval request created)'}"
          ),
          conversation: conversation
        )
      end

      {
        reply: "got your $#{fmt_amt(amt)} - that size needs a quick teammate sign-off before i load it. won't take long!",
        labels: %w[over-threshold-hold needs-human]
      }
    end

    def record_api_result(agent_game, result)
      return unless agent_game && result.is_a?(Hash) && result.key?(:ok)
      result[:ok] ? agent_game.record_api_success! : agent_game.record_api_failure!
    rescue StandardError => e
      Rails.logger.error("[Orchestrator] record_api_result failed: #{e.message}")
    end

    # Feature 3 — cashout velocity. Returns {exceeded, count, hours, threshold}.
    def cashout_velocity_state
      pref = reply_pref_cached
      threshold = fraud_int(pref, :fraud_cashout_velocity_count, 3)
      hours = fraud_int(pref, :fraud_cashout_velocity_hours, 24)
      count = GameAction.where(account_id: account.id, contact_id: contact.id, action_type: 'cashout', status: 'success')
                        .where('created_at >= ?', hours.hours.ago)
                        .count
      { exceeded: threshold.positive? && count >= threshold, count: count, hours: hours, threshold: threshold }
    rescue StandardError => e
      Rails.logger.error("[Orchestrator] cashout_velocity_state failed: #{e.message}")
      { exceeded: false, count: 0, hours: 24, threshold: 3 }
    end

    def fraud_int(pref, name, default)
      return default unless pref.respond_to?(name)
      v = pref.public_send(name)
      v.nil? ? default : v.to_i
    rescue StandardError
      default
    end

    # Feature 4 — duplicate-payment guard.
    def duplicate_payment_check_enabled?
      pref = reply_pref_cached
      return true unless pref.respond_to?(:fraud_duplicate_payment_check)
      v = pref.fraud_duplicate_payment_check
      v.nil? ? true : v
    rescue StandardError
      true
    end

    def duplicate_recent_load?(amount)
      amt = amount.to_f
      return false if amt <= 0
      GameAction.where(account_id: account.id, contact_id: contact.id, action_type: 'load', status: 'success', amount: amt)
                .where('created_at >= ?', 10.minutes.ago)
                .exists?
    rescue StandardError => e
      Rails.logger.error("[Orchestrator] duplicate_recent_load? failed: #{e.message}")
      false
    end

    # ---- create-on-transfer (wired into the existing yes/no confirmation handler) ----

    def store_pending_transfer_create(slug, amount)
      attrs = (contact.custom_attributes || {}).merge(
        'pending_transfer_create' => { 'target_slug' => slug, 'amount' => amount.to_f }
      )
      contact.update(custom_attributes: attrs)
    rescue StandardError => e
      Rails.logger.error("[Orchestrator] store_pending_transfer_create failed: #{e.message}")
    end

    def clear_pending_transfer_create
      attrs = (contact.custom_attributes || {}).dup
      attrs.delete('pending_transfer_create')
      contact.update(custom_attributes: attrs)
    rescue StandardError => e
      Rails.logger.error("[Orchestrator] clear_pending_transfer_create failed: #{e.message}")
    end

    def complete_pending_transfer_create(pending)
      pending = pending.is_a?(Hash) ? pending.stringify_keys : {}
      slug = pending['target_slug']
      amount = pending['amount'].to_f
      clear_pending_transfer_create

      ag = pick_agent_game(slug)
      return { reply: unavailable_game_reply(slug), labels: ['game-unavailable'] } unless ag

      executor = Games::ActionExecutor.new(agent_game: ag, contact: contact, conversation: conversation)
      add_result, username, = attempt_auto_add_player(executor, ag.game.slug, metadata: { source: 'bella_transfer_create' })
      record_api_result(ag, add_result)

      failure_response = add_player_failure_response(ag, add_result)
      return failure_response if failure_response

      unless add_result[:ok]
        safe_telegram { Games::TelegramNotifier.load_failed(add_result[:action]) if add_result[:action] }
        safe_telegram do
          Games::TelegramNotifier.human_escalation(
            account: account, contact: contact,
            reason: escalation_context(
              wants: "a #{ag.game.name} account to receive their transferred money",
              done: "cashed-out funds are waiting; account creation FAILED (#{add_result[:error]})",
              left: 'money cashed out but not delivered',
              suggest: 'create the account manually, then load the waiting amount',
              need: "account + load for #{contact.name}, then confirm in chat"
            ),
            conversation: conversation
          )
        end
        return { reply: "hit a snag setting up your #{ag.game.name} account — flagged a teammate.", labels: ['account-creation-failed', 'needs-human'] }
      end

      password = add_result[:password]
      store_game_username(ag.game.slug, username)
      store_game_password(ag.game.slug, password)

      if amount > 0
        load_result = executor.load_player(
          game_username: username,
          amount: amount,
          metadata: { source: 'bella_transfer_create', conversation_id: conversation&.id }
        )
        record_api_result(ag, load_result)

        if load_result[:ok]
          safe_telegram do
            Games::TelegramNotifier.human_escalation(
              account: account, contact: contact,
              reason: "Transfer-create: set up #{username} on #{ag.game.name} and loaded $#{fmt_amt(amount)}",
              conversation: conversation
            )
          end
          return { reply: "you're all set up on #{ag.game.name}! username: #{username}, password: #{password} (save this!) — loaded $#{fmt_amt(amount)}.", labels: ['transfer-create-complete', 'new-account-created'] }
        end

        safe_telegram { Games::TelegramNotifier.load_failed(load_result[:action]) if load_result[:action] }
        safe_telegram do
          Games::TelegramNotifier.human_escalation(
            account: account, contact: contact,
            reason: escalation_context(
              wants: "their transferred $#{fmt_amt(amount)} on the new #{ag.game.name} account",
              done: "account #{username} CREATED, creds sent; load FAILED (#{load_result[:error]})",
              left: "$#{fmt_amt(amount)} cashed out but not loaded",
              suggest: 'load it on the panel - account already exists',
              need: "load $#{fmt_amt(amount)} to #{username}, then confirm in chat"
            ),
            conversation: conversation
          )
        end
        return { reply: "set up your #{ag.game.name} account (username: #{username}, password: #{password}) but hit a snag loading $#{fmt_amt(amount)} — a teammate will finish it.", labels: ['account-created', 'load-failed', 'needs-human'] }
      end

      { reply: "you're all set up on #{ag.game.name}! username: #{username}, password: #{password} (save this!)", labels: ['transfer-create-complete', 'new-account-created'] }
    end

    def fmt_amt(num)
      f = num.to_f
      f == f.to_i ? f.to_i.to_s : format('%.2f', f)
    end

    def slug_label(slug)
      return 'that game' if slug.blank?
      (Game.find_by(slug: slug)&.name.presence || slug.to_s.tr('_', ' '))
    rescue StandardError
      slug.to_s.tr('_', ' ')
    end

    def handle_whats_hitting(intent)
      games_text = active_games_list_text
      reply = games_text.present? ? "right now we have: #{games_text} — which one do you want loaded?" : "let me check which games are available and get back to you!"
      { reply: reply, labels: [] }
    end

    # ---- Info / link / question handlers (Batch: AI brain completion) ----

    # [game, game_rule] for a slug, scoped to this account. Either may be nil.
    def game_and_rule(slug)
      game = Game.find_by(slug: slug)
      rule = game ? GameRule.find_by(account_id: account.id, game_id: game.id) : nil
      [game, rule]
    rescue StandardError
      [nil, nil]
    end

    def handle_request_game_link(intent)
      game_slug = chosen_game_slug(intent)
      return { reply: "which game you wanna play? we got #{active_games_list_text}", labels: ['needs-game'] } unless game_slug

      game, rule = game_and_rule(game_slug)
      name = game&.name.presence || game_slug.tr('_', ' ')
      web = rule&.game_web_url.presence || game&.domain.presence
      return { reply: "here you go — play #{name} here: #{web}", labels: ['game-link'] } if web.present?

      download = rule&.game_download_url.presence || game&.player_signup_url.presence
      return { reply: "no web version for #{name} — you can download and play! #{download}", labels: ['game-link'] } if download.present?

      safe_telegram do
        Games::TelegramNotifier.human_escalation(account: account, contact: contact, reason: escalation_context(wants: "a link to play #{name}", done: 'no web/download URL configured for this game', left: 'player cannot open the game', suggest: 'send the link by hand and add it in game settings', need: "the #{name} link"), conversation: conversation)
      end
      { reply: 'let me grab that link for you, one sec!', labels: %w[needs-human cashier-action-needed] }
    end

    def handle_request_download_link(intent)
      game_slug = chosen_game_slug(intent)
      return { reply: "which game you wanna download? we got #{active_games_list_text}", labels: ['needs-game'] } unless game_slug

      game, rule = game_and_rule(game_slug)
      name = game&.name.presence || game_slug.tr('_', ' ')
      dl = rule&.game_download_url.presence || game&.player_signup_url.presence
      return { reply: "here's the #{name} download: #{dl}", labels: ['download-link'] } if dl.present?

      safe_telegram do
        Games::TelegramNotifier.human_escalation(account: account, contact: contact, reason: escalation_context(wants: "the #{name} download link", done: 'no download URL configured for this game', left: 'player cannot install the game', suggest: 'send it by hand and add it in game settings', need: "the #{name} download link"), conversation: conversation)
      end
      { reply: 'let me grab that download link for you, one sec!', labels: %w[needs-human cashier-action-needed] }
    end

    # App link == download link (the app IS the download).
    def handle_request_app_link(intent)
      handle_request_download_link(intent)
    end

    def handle_cashout_rules(intent)
      game_slug = chosen_game_slug(intent)
      return { reply: "which game you asking about? we got #{active_games_list_text}", labels: ['needs-game'] } unless game_slug

      game, rule = game_and_rule(game_slug)
      name = game&.name.presence || game_slug.tr('_', ' ')

      if rule
        min_amt = rule.cashout_min_amount.to_f
        max_amt = rule.cashout_max_amount.to_f
        min_mult = rule.cashout_min_multiplier.to_f
        if min_amt.positive? || max_amt.positive? || min_mult.positive?
          parts = []
          parts << "min cashout is $#{fmt_amt(min_amt)}" if min_amt.positive?
          parts << "max $#{fmt_amt(max_amt)}" if max_amt.positive?
          parts << "gotta hit #{fmt_amt(min_mult)}x your deposit" if min_mult.positive?
          return { reply: "for #{name}: #{parts.join(', ')}", labels: ['cashout-rules'] }
        end
        return { reply: rule.cashout_rules_text.to_s, labels: ['cashout-rules'] } if rule.cashout_rules_text.present?
      end

      safe_telegram do
        Games::TelegramNotifier.human_escalation(account: account, contact: contact, reason: escalation_context(wants: "the cashout rules for #{name}", done: 'no cashout rules configured for this game', left: 'player waiting on an answer', suggest: 'reply with the house rules and save them in game settings', need: "cashout rules for #{name}"), conversation: conversation)
      end
      { reply: 'let me get you the exact cashout rules, one sec!', labels: %w[needs-human cashier-action-needed] }
    end

    def handle_list_platforms(intent)
      asked_slug = intent.is_a?(Hash) ? intent[:game_slug] : nil
      if asked_slug.present? && pick_agent_game(asked_slug).nil?
        game = Game.find_by(slug: asked_slug)
        name = game&.name.presence || asked_slug.tr('_', ' ')
        return { reply: "#{name}'s not active right now — we'll let you know when it's back!", labels: ['list-platforms'] }
      end

      list = active_games_list_text
      return { reply: "we got #{list} — which one you want?", labels: ['list-platforms'] } if list.present? && list != 'no games'

      { reply: 'let me pull up our games and get right back to you!', labels: %w[needs-human cashier-action-needed] }
    end

    # SAFETY: returns platform TYPES only — NEVER a handle, verification_email, or
    # verification_email_password. The handle is revealed only during real payment
    # processing (handle_payment_method_chosen), never in answer to a question.
    def handle_payment_method_question(intent)
      if payment_reply_source_pref == 'handles'
        return payment_question_from_platforms
      end

      canned = begin
        CannedResponse.find_by(account_id: account.id, short_code: 'payment')
      rescue StandardError
        nil
      end
      return { reply: canned.content.to_s, labels: ['payment-method-question'] } if canned&.content.present?

      payment_question_from_platforms
    end

    # Lists DISTINCT active platform names only (no handles).
    def payment_question_from_platforms
      platforms = active_payment_platforms.map { |p| pretty_platform(p) }.reject(&:blank?).uniq
      return { reply: "we take #{humanize_list(platforms)}", labels: ['payment-method-question'] } if platforms.present?

      { reply: "let me check which payment methods we've got active and get right back to you!", labels: %w[needs-human cashier-action-needed] }
    end

    def payment_reply_source_pref
      pref = reply_pref_cached
      return 'canned' unless pref.respond_to?(:payment_reply_source)
      (pref.payment_reply_source.presence || 'canned').to_s
    rescue StandardError
      'canned'
    end

    def pretty_platform(platform)
      case platform.to_s.downcase
      when 'cashapp' then 'cash app'
      when 'chime'   then 'chime'
      when 'venmo'   then 'venmo'
      when 'paypal'  then 'paypal'
      when 'zelle'   then 'zelle'
      else platform.to_s
      end
    end

    def humanize_list(items)
      items = Array(items).reject(&:blank?)
      return '' if items.empty?
      return items.first if items.size == 1
      return items.join(' and ') if items.size == 2
      "#{items[0..-2].join(', ')}, and #{items.last}"
    end

    # G3 (June 10) - referral on the shared generosity pattern. referral_enabled
    # (the BUG-4 master switch, default OFF) keeps the existing auto-pay path
    # when ON. OFF = launch default: full case to Telegram + pending
    # ApprovalRequest; approval pays the referrer through the normal load path
    # (Approvals::AutoResume load branch).
    def handle_referral(intent)
      referral = begin
        Games::ReferralBonusService.create(account: account, referrer_contact: contact)
      rescue StandardError => e
        Rails.logger.error("[Orchestrator] ReferralBonusService failed: #{e.message}")
        nil
      end

      pref = reply_pref_cached
      if pref.respond_to?(:referral_enabled) && pref.referral_enabled
        # Configured ON: the BUG-4 auto-pay path fires from link_referred once
        # the referred player is linked (and deposits, if required). Just ack.
        return { reply: "thanks for the referral! i've noted it - your bonus hits as soon as your friend gets going", labels: ['referral-pending'] }
      end

      escalate_referral_claim(referral)
    end

    # G3 - reward math: 'fixed' -> referral_fixed_amount; 'percent_of_deposit'
    # (default) -> referral_percent (default 10) of the referred player's most
    # recent real deposit. 0 = reward TBD (no deposit yet / below the minimum).
    def referral_reward_amount(referred_contact)
      mode = (generosity_setting('referral_reward_mode').presence || 'percent_of_deposit').to_s.strip
      return generosity_setting('referral_fixed_amount').to_f.round(2) if mode == 'fixed'

      pct = generosity_setting('referral_percent').to_f
      pct = 10.0 unless pct.positive?
      return 0.0 unless referred_contact

      dep = GameAction.where(account_id: account.id, contact_id: referred_contact.id,
                             action_type: 'load', status: 'success')
                      .where("COALESCE(metadata->>'freeplay', 'false') != 'true'")
                      .order(created_at: :desc).first&.amount.to_f
      min_dep = generosity_setting('referral_min_deposit').to_f
      return 0.0 if min_dep.positive? && dep < min_dep

      (dep * pct / 100.0).round(2)
    rescue StandardError => e
      Rails.logger.error("[Orchestrator] referral_reward_amount failed: #{e.message}")
      0.0
    end

    # First active agent_game the contact actually has a username on.
    def primary_agent_game_for_contact
      attrs = contact.custom_attributes || {}
      account.agent_games.where(status: 'active').includes(:game).to_a
             .find { |a| attrs["game_username_#{a.game.slug}"].present? }
    rescue StandardError
      nil
    end

    # G3a OFF (launch default) - full case + pending approval; approve pays A.
    def escalate_referral_claim(referral)
      if recent_generosity_rejection?('bella_referral')
        log_generosity_decision(kind: 'referral', decision: 'denied', amount: 0, source: 'operator_reject')
        return { reply: "can't pay that referral right now - a teammate already looked at it", labels: ['referral-denied'] }
      end

      referred = referral&.referred_contact
      reward = referral_reward_amount(referred)
      mode = (generosity_setting('referral_reward_mode').presence || 'percent_of_deposit').to_s
      pay_ag = primary_agent_game_for_contact
      pay_slug = pay_ag&.game&.slug
      username = pay_slug ? (contact.custom_attributes || {})["game_username_#{pay_slug}"] : nil
      data = generosity_case_data(pay_slug)
      referred_txt = referred ? "#{referred.name} (linked)" : 'not linked yet'
      reward_txt = reward.positive? ? "$#{fmt_amt(reward)} (#{mode})" : "TBD (#{mode} - referred player hasn't deposited yet)"

      approval = create_pending_generosity_approval(
        source: 'bella_referral', amount: reward, game_slug: pay_slug.to_s,
        username: username,
        extra: { 'referral' => 'true', 'referral_id' => referral&.id.to_s,
                 'reward_pending_referred_deposit' => (reward.positive? ? 'false' : 'true') }
      )

      safe_telegram do
        Games::TelegramNotifier.human_escalation(
          account: account, contact: contact,
          reason: escalation_context(
            wants: "referral reward - #{contact.name} referred #{referred ? referred.name : 'a friend (not linked yet)'}",
            done: "case: referrer lifetime deposits $#{fmt_amt(data[:total_deposits])} (#{data[:deposit_count]}); referred: #{referred_txt}; reward if approved: #{reward_txt}",
            left: 'no reward paid - referrals are operator-approved right now (referral_enabled off)',
            suggest: reward.positive? ? "approve the $#{fmt_amt(reward)} reward" : 'wait for the referred player to deposit, or set referral_fixed_amount',
            need: "approve or decline the referral reward for #{contact.name}#{approval_ref_text(approval)}"
          ),
          conversation: conversation
        )
      end
      log_generosity_decision(kind: 'referral', decision: 'escalated', amount: reward, source: 'default_master_off')
      { reply: "thanks for the referral! i've flagged it - your reward lands once a teammate confirms it", labels: %w[referral-pending needs-human] }
    end

    def handle_redeem_partial_replay(intent)
      game_slug = chosen_game_slug(intent)
      return { reply: 'which game do you want to cash part of out from?', labels: ['partial-needs-game'] } unless game_slug

      msg = (latest_customer_text || recent_customer_text).to_s
      # TAB A fix: prefer the number right after the cashout verb - first-number
      # parsing cashed out the wrong amount on "keep 30 in and cash out 50".
      verb_m = msg.match(/(?:cash\s*out|cashout|redeem|withdraw|payout|take\s+out)\s+\$?(\d+(?:\.\d{1,2})?)/i)
      amount = verb_m ? verb_m[1].to_f : msg.scan(/\$?(\d+(?:\.\d{1,2})?)/).flatten.first&.to_f
      # R5 - the kept-in amount ("cash out 30, keep 20" -> 20). Recorded after a
      # successful cashout as a NEW deposit so it drives the next rules.
      keep_m = msg.match(/(?:keep|leave)\s+(?:the\s+)?\$?(\d+(?:\.\d{1,2})?)/i)
      keep_amount = keep_m ? keep_m[1].to_f : nil
      if amount.nil? || amount <= 0
        return { reply: 'how much do you want to cash out? the rest stays in to play', labels: ['partial-needs-amount'] }
      end

      username = find_game_username_for_slug(contact, game_slug)
      unless username
        return { reply: "what's your #{game_slug} username? need it to cash out part of your balance.", labels: ['partial-needs-username'] }
      end

      ag = pick_agent_game(game_slug)
      return { reply: unavailable_game_reply(game_slug), labels: ['game-unavailable'] } unless ag

      # Cash out ONLY the requested partial amount; the rest stays in the game to play.
      executor = Games::ActionExecutor.new(agent_game: ag, contact: contact, conversation: conversation)
      if recent_cashout_duplicate?(agent_game: ag, amount: amount)
        Rails.logger.info("[Orchestrator] redeem-partial DEDUP: $#{fmt_amt(amount)} on #{ag.game.name} within #{CASHOUT_DEDUP_WINDOW_SECONDS}s — skipping duplicate")
        return { reply: "already processing your $#{fmt_amt(amount)} cashout — hang tight!", labels: ['partial-cashout', 'duplicate-skipped'] }
      end
      result = executor.cashout_player(
        game_username: username,
        amount: amount,
        metadata: { source: 'bella_partial_replay', conversation_id: conversation&.id }
      )

      if result[:ok]
        keep_note = record_keep_in_deposit(ag, keep_amount, result)
        safe_telegram do
          Games::TelegramNotifier.human_escalation(
            account: account, contact: contact,
            reason: "#{contact.name} partial cashout $#{fmt_amt(amount)} on #{ag.game.name}, rest left to play#{keep_note}",
            conversation: conversation
          )
        end
        {
          reply: "cashed out $#{fmt_amt(amount)} — the rest is still in your #{ag.game.name} account to play!",
          labels: ['partial-cashout', 'cashier-action-needed']
        }
      else
        safe_telegram { Games::TelegramNotifier.load_failed(result[:action]) if result[:action] }
        safe_telegram do
          Games::TelegramNotifier.human_escalation(
            account: account, contact: contact,
            reason: escalation_context(
              wants: "cash out $#{fmt_amt(amount)} and keep playing with the rest on #{ag.game.name}",
              done: "partial cashout FAILED (#{result[:error]}, code #{result[:code]}) - nothing moved",
              left: 'the partial cashout',
              suggest: 'run it on the panel once it cooperates',
              need: "cash out $#{fmt_amt(amount)} for #{username}, then confirm in chat"
            ),
            conversation: conversation
          )
        end
        {
          reply: "hit a snag cashing out your $#{fmt_amt(amount)} — flagged a teammate, they'll sort it in a couple minutes.",
          labels: ['cashout-failed', 'needs-human']
        }
      end
    end

    # R5 - records the kept-in part of a partial cashout as a NEW deposit
    # (GameAction load/success, NO panel call - that money never left the game).
    # It becomes the most recent deposit for R3 min/max and R1 deposit_only math.
    # Returns the Telegram note fragment, or '' if nothing was recorded.
    def record_keep_in_deposit(ag, keep_amount, cashout_result)
      amt = keep_amount.to_f
      return '' if amt <= 0

      cashout_action_id = cashout_result.is_a?(Hash) ? cashout_result[:action]&.id : nil
      GameAction.create!(
        account_id: account.id,
        agent_game_id: ag.id,
        contact_id: contact&.id,
        conversation_id: conversation&.id,
        action_type: 'load',
        order_id: "keepin_#{cashout_action_id || SecureRandom.hex(6)}",
        game_username: find_game_username_for_slug(contact, ag.game.slug),
        amount: amt,
        status: 'success',
        metadata: { 'keep_in_from_cashout' => true, 'source' => 'bella_partial_keep_in',
                    'cashout_action_id' => cashout_action_id },
        executed_at: Time.current
      )
      ". RELOAD (keep-in-from-cashout): $#{fmt_amt(amt)} recorded as the new deposit - NOT a fresh deposit"
    rescue StandardError => e
      Rails.logger.error("[Orchestrator] record_keep_in_deposit failed: #{e.message}")
      ''
    end

    def handle_new_account_reissue(intent)
      game_slug = chosen_game_slug(intent)
      ag = pick_agent_game(game_slug)
      return { reply: unavailable_game_reply(game_slug), labels: ['game-unavailable'] } unless ag

      # Existing account is broken/locked — clear the stale creds, then mint a fresh one
      # using the exact same replace-path helper handle_account_creation_request uses.
      clear_game_credentials(ag.game.slug)

      executor = Games::ActionExecutor.new(agent_game: ag, contact: contact, conversation: conversation)
      add_result, auto_username, = attempt_auto_add_player(executor, ag.game.slug, metadata: { source: 'bella_account_reissue' })

      failure_response = add_player_failure_response(ag, add_result)
      return failure_response if failure_response

      unless add_result[:ok]
        safe_telegram { Games::TelegramNotifier.load_failed(add_result[:action]) if add_result[:action] }
        # R6c - walk the ladder down (suggest a different game + Telegram human
        # with full R8 context) instead of dead-ending.
        return ladder_end_response(ag, after: "reissue: account creation failed (#{add_result[:error]})")
      end

      generated_password = add_result[:password]
      store_game_username(ag.game.slug, auto_username)
      store_game_password(ag.game.slug, generated_password)

      {
        reply: "all fixed! your new #{ag.game.name} account — username: #{auto_username}, password: #{generated_password} (save this!)",
        labels: ['account-reissued', 'new-account-created']
      }
    end

    def handle_replay_from_balance(intent)
      # Read-only: confirms the player's existing in-game balance. Moves NO money.
      game_slug = chosen_game_slug(intent)
      return { reply: 'which game do you want to keep playing on?', labels: ['replay-needs-game'] } unless game_slug

      username = find_game_username_for_slug(contact, game_slug)
      unless username
        return { reply: "I don't have your #{game_slug} account on file — what's your username?", labels: ['replay-needs-username'] }
      end

      ag = pick_agent_game(game_slug)
      return { reply: unavailable_game_reply(game_slug), labels: ['game-unavailable'] } unless ag

      balance =
        begin
          Games::ActionExecutor.new(agent_game: ag, contact: contact, conversation: conversation)
                               .check_player_balance(game_username: username)
        rescue StandardError => e
          Rails.logger.error("[Orchestrator] replay_from_balance balance read failed: #{e.message}")
          nil
        end

      if balance.nil?
        safe_telegram do
          Games::TelegramNotifier.human_escalation(
            account: account, contact: contact,
            reason: escalation_context(
              wants: "to keep playing their existing #{ag.game.name} balance",
              done: "balance read FAILED for #{username} - no number given to the player",
              left: 'player does not know their balance',
              suggest: 'check the panel and tell them the real figure',
              need: "the real #{ag.game.name} balance for #{username}"
            ),
            conversation: conversation
          )
        end
        return { reply: "let me double-check your #{ag.game.name} balance — one sec", labels: %w[cashier-action-needed replay-from-balance] }
      end

      if balance.to_f <= 0
        return { reply: "looks like your #{ag.game.name} balance is empty — want to load up?", labels: ['replay-from-balance'] }
      end

      { reply: "you've got $#{fmt_amt(balance)} on #{ag.game.name} — you're good to play!", labels: ['replay-from-balance'] }
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

    # R8 - builds a full-situation escalation message in plain language so the
    # human reading Telegram knows the whole picture without opening the app:
    # what the player wants, what already happened, what is still left, what
    # Bella suggests, and what she needs from the human. Used by the
    # escalations this run touches (R1 half-fail, R6 ladder-end, R7
    # over-threshold). System-wide rollout to untouched handlers is Run 3.
    def escalation_context(wants:, done: nil, left: nil, suggest: nil, need: nil)
      parts = []
      parts << "PLAYER WANTS: #{wants}"
      parts << "ALREADY DONE: #{done}" if done.to_s.strip.length.positive?
      parts << "STILL LEFT: #{left}" if left.to_s.strip.length.positive?
      parts << "BELLA SUGGESTS: #{suggest}" if suggest.to_s.strip.length.positive?
      parts << "NEEDS FROM HUMAN: #{need}" if need.to_s.strip.length.positive?
      parts.join(' | ')
    end

    # MEGA2 P4 - approval reference for Telegram texts so the ops group can
    # act with 'approve <id>' / 'deny <id>' (TelegramOps::CommandHandler).
    def approval_ref_text(approval)
      return ' (request already pending)' if approval == :already
      return '' unless approval.respond_to?(:id) && approval.id

      " - approval ##{approval.id}: reply 'approve #{approval.id}' or 'deny #{approval.id}'"
    end

    def apply_receipt_preference(result)
      return result unless result.is_a?(Hash) && result[:reply].present?

      begin
        pref = ReplyPreference.for_account(account.id)
        if pref&.auto_send_receipt == false
          result = result.dup
          result[:reply] = result[:reply].gsub(/loaded\s*✅?/i, '').gsub(/✅/, '').strip
          result[:reply] = 'done' if result[:reply].blank?
        end
      rescue StandardError
      end
      result
    end

    # MEGA2 P1 - referral-hijack fix. The old version linked the NEWEST
    # account-wide pending Referral (referred_contact_id nil) to WHOEVER
    # created an account next - any stranger absorbed someone else's referral
    # credit. Link ONLY on a deterministic match: exactly ONE pending Referral
    # already referencing THIS contact (referred_contact_id is the only
    # linkage column on referrals - no conversation_id / metadata exists).
    # Otherwise leave every pending row untouched and escalate once per
    # contact (idempotent via the escalated-ids stamp). Zero pendings = no-op.
    # referral_enabled stays the master pay switch inside link_referred ->
    # check_and_pay, so nothing auto-pays while it is off (today's default).
    def link_referred_on_account_creation
      begin
        pendings = Referral.where(account_id: account.id, status: 'pending')
        return if pendings.none?

        mine = pendings.where(referred_contact_id: contact.id).limit(2).to_a
        if mine.size == 1
          Games::ReferralBonusService.new(account: account).link_referred(
            referral: mine.first,
            referred_contact: contact
          )
          Rails.logger.info("[Orchestrator] Linked referral #{mine.first.id} to #{contact.name} (deterministic)")
          return
        end

        pending_ids = pendings.order(:id).pluck(:id)
        already = Array((contact.custom_attributes || {})['referral_link_escalated_ids']).map(&:to_i)
        return if (pending_ids - already).empty?

        safe_telegram do
          Games::TelegramNotifier.human_escalation(
            account: account, contact: contact,
            reason: escalation_context(
              wants: 'referral credit (pending referral(s) exist but none deterministically match this player)',
              done: "account created for #{contact.name}; #{pending_ids.size} pending referral(s) (ids #{pending_ids.join(', ')}) - NONE linked, nothing paid",
              left: 'verify who referred them',
              suggest: 'check the referral list and link the right one by hand',
              need: 'confirm the referrer and approve the link (or ignore if unrelated)'
            ),
            conversation: conversation
          )
        end
        attrs = (contact.custom_attributes || {})
        contact.update(custom_attributes: attrs.merge('referral_link_escalated_ids' => (already + pending_ids).uniq))
      rescue StandardError => e
        Rails.logger.error("[Orchestrator] Referral link failed: #{e.message}")
      end
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

    def execute_game_api(game_slug:, action:, username:, amount: nil, metadata: nil, order_id: nil)
      ag = pick_agent_game(game_slug)
      return { success: false, error: 'game unavailable' } unless ag

      executor = Games::ActionExecutor.new(agent_game: ag, contact: contact, conversation: conversation)

      case action.to_s
      when 'recharge', 'load'
        result = executor.load_player(
          game_username: username,
          amount: amount,
          metadata: metadata || { source: 'bella_orchestrator' },
          order_id: order_id
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
