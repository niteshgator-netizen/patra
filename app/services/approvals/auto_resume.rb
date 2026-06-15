# frozen_string_literal: true

# F15 — approval-gate auto-resume, SHIPPED DARK.
# When ENV PATRA_APPROVAL_AUTORESUME=true, approving a cashout ApprovalRequest
# executes the ORIGINAL cashout exactly once. Default off: approving keeps
# today's manual behavior (record updated, human executes by hand).
#
# Exactly-once: order_id "appr_<approval id>" rides the game_actions
# (account_id, order_id) unique index — double-approve, job retries, and
# concurrent approvals all collapse to one execution.
module Approvals
  class AutoResume
    def self.enabled?
      ENV['PATRA_APPROVAL_AUTORESUME'].to_s.casecmp('true').zero?
    end

    def self.execute!(approval)
      return { ok: false, skipped: :disabled } unless enabled?
      return { ok: false, skipped: :not_approved } unless approval.status == 'approved'
      # MONEYFLOWS3 G1-G3: approved generosity/over-threshold LOADS execute through
      # the same exactly-once machinery (appr_<id> order_id). Anything without an
      # AgentGame target + username + positive amount stays manual (notified).
      return execute_load!(approval) if approval.action_type == 'load'
      return { ok: false, skipped: :not_cashout } unless approval.action_type == 'cashout'

      agent_game = approval.target_type == 'AgentGame' ? AgentGame.find_by(id: approval.target_id) : nil
      meta = (approval.metadata || {}).stringify_keys
      username = meta['game_username'].to_s.strip
      amount = approval.amount.to_f

      if agent_game.nil? || username.blank? || amount <= 0
        Rails.logger.error("[AutoResume] approval ##{approval.id} not executable (ag=#{agent_game&.id} user=#{username.inspect} amount=#{amount})")
        notify(approval, "⚠️ Approved cashout ##{approval.id} could NOT auto-execute (missing game/username/amount) — handle manually")
        return { ok: false, skipped: :invalid }
      end

      order_id = "appr_#{approval.id}"
      if (existing = GameAction.find_by(account_id: approval.account_id, order_id: order_id))
        Rails.logger.info("[AutoResume] approval ##{approval.id} already executed (status=#{existing.status}) — no-op")
        return { ok: true, already: true, status: existing.status }
      end

      executor = Games::ActionExecutor.new(agent_game: agent_game, contact: nil, conversation: nil)
      result = begin
        executor.cashout_player(
          game_username: username,
          amount: amount,
          metadata: meta.merge('source' => 'approval_autoresume', 'approval_request_id' => approval.id),
          order_id: order_id,
          skip_approval_gate: true
        )
      rescue Games::ActionExecutor::IdempotencyError, ActiveRecord::RecordNotUnique
        Rails.logger.info("[AutoResume] approval ##{approval.id} raced — already executed elsewhere")
        return { ok: true, already: true }
      end

      if result[:ok]
        notify(approval, "✅ Approved cashout EXECUTED: $#{amount} for #{username} on #{agent_game.game&.name} (approval ##{approval.id})")
      else
        action_status = GameAction.find_by(account_id: approval.account_id, order_id: order_id)&.status || 'not created'
        notify(approval,
               "❌ Approved cashout ##{approval.id} FAILED: #{result[:error]} (code #{result[:code]}) — " \
               "action status=#{action_status}, $#{amount} for #{username} NEEDS HUMAN — verify on the panel before paying")
      end
      result
    end

    # MONEYFLOWS3 - approved LOAD (freeplay/bonus/referral/over-threshold) executes
    # once through the normal ActionExecutor path. Metadata flags from the approval
    # ride into the GameAction so R3 deposit-typing and TABA-1 single-record hold.
    def self.execute_load!(approval)
      agent_game = approval.target_type == 'AgentGame' ? AgentGame.find_by(id: approval.target_id) : nil
      meta = (approval.metadata || {}).stringify_keys
      username = meta['game_username'].to_s.strip
      amount = approval.amount.to_f

      if agent_game.nil? || username.blank? || amount <= 0
        Rails.logger.error("[AutoResume] load approval ##{approval.id} not executable (ag=#{agent_game&.id} user=#{username.inspect} amount=#{amount})")
        notify(approval, "Approved load ##{approval.id} could NOT auto-execute (missing game/username/amount) - handle manually")
        return { ok: false, skipped: :invalid }
      end

      order_id = "appr_#{approval.id}"
      if (existing = GameAction.find_by(account_id: approval.account_id, order_id: order_id))
        Rails.logger.info("[AutoResume] load approval ##{approval.id} already executed (status=#{existing.status}) - no-op")
        return { ok: true, already: true, status: existing.status }
      end

      contact = Contact.find_by(id: meta['contact_id'], account_id: approval.account_id)
      flags = {}
      flags['freeplay'] = true if meta['source'] == 'bella_freeplay' || meta['freeplay'].to_s == 'true'
      flags['deposit_bonus'] = true if meta['source'] == 'bella_bonus' || meta['deposit_bonus'].to_s == 'true'
      flags['referral'] = true if meta['source'] == 'bella_referral' || meta['referral'].to_s == 'true'

      executor = Games::ActionExecutor.new(agent_game: agent_game, contact: contact, conversation: nil)
      result = begin
        executor.load_player(
          game_username: username,
          amount: amount,
          metadata: meta.slice('source', 'contact_id', 'payment_id', 'deposit_amount', 'bonus_amount', 'referral_id')
                        .merge(flags)
                        .merge('approval_request_id' => approval.id),
          order_id: order_id
        )
      rescue Games::ActionExecutor::IdempotencyError, ActiveRecord::RecordNotUnique
        Rails.logger.info("[AutoResume] load approval ##{approval.id} raced - already executed elsewhere")
        return { ok: true, already: true }
      end

      if result[:ok]
        notify(approval, "Approved load EXECUTED: $#{amount} for #{username} on #{agent_game.game&.name} (#{meta['source']}, approval ##{approval.id})")
        # it9 — DARK scaffold: tell the customer their approved freeplay landed. The load ALREADY
        # ran once above (guarded by the appr_<id> order_id), so this only SENDS a message and can
        # never double-load. Flag off => no customer message (byte-identical to today).
        notify_customer_freeplay(approval, contact, amount, agent_game.game&.name) if flags['freeplay']
      else
        action_status = GameAction.find_by(account_id: approval.account_id, order_id: order_id)&.status || 'not created'
        notify(approval,
               "Approved load ##{approval.id} FAILED: #{result[:error]} (code #{result[:code]}) - " \
               "action status=#{action_status}, $#{amount} for #{username} NEEDS HUMAN")
      end
      result
    end

    # safe_telegram: alert failure must never affect execution state reporting.
    def self.notify(approval, text)
      Games::TelegramNotifier.send_to_cashout_group(text, account: approval.account)
    rescue StandardError => e
      Rails.logger.error("[AutoResume] telegram failed approval=#{approval.id}: #{e.class}: #{e.message}")
    end

    # it9 — notify-back SCAFFOLD (DARK behind PATRA_FREEPLAY_NOTIFY_ENABLED, default off). After an
    # APPROVED freeplay has ALREADY been loaded by execute_load! (load_player ran exactly once,
    # guarded by the appr_<id> order_id idempotency), tell the customer their freeplay landed. This
    # method ONLY creates an outgoing message — it NEVER loads, so it cannot double-load. With the
    # flag off it returns immediately (no customer message = today's behavior). Best-effort: any
    # failure is logged and swallowed so it can never affect the load result.
    def self.notify_customer_freeplay(approval, contact, amount, game_name)
      return unless ENV['PATRA_FREEPLAY_NOTIFY_ENABLED'].to_s.casecmp('true').zero?
      return unless contact

      # it9-close — only ever message an OPEN conversation (never closed/resolved/pending/snoozed),
      # most-recently-active first. The approval (target AgentGame) carries no conversation_id or
      # inbox, so the correct inbox isn't determinable here — the latest OPEN thread is the active
      # one the customer is waiting in. If there's NO open conversation, send NOTHING (return
      # quietly): the customer simply doesn't get the auto-note. Never picks a stale/wrong-status thread.
      conv = Conversation.where(account_id: approval.account_id, contact_id: contact.id)
                         .open
                         .order(updated_at: :desc).first
      return unless conv

      amt = format('%g', amount.to_f)
      conv.messages.create!(
        account: approval.account,
        inbox: conv.inbox,
        content: "good news — your $#{amt} freeplay just landed#{game_name ? " on #{game_name}" : ''}, good luck! 🎰",
        message_type: :outgoing,
        additional_attributes: { 'freeplay_notify' => true, 'approval_request_id' => approval.id }
      )
    rescue StandardError => e
      Rails.logger.warn("[AutoResume] freeplay notify-back failed approval=#{approval.id}: #{e.class}: #{e.message}")
    end
  end
end
