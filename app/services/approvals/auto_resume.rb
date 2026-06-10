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
      return { ok: false, skipped: :not_cashout } unless approval.action_type == 'cashout'
      return { ok: false, skipped: :not_approved } unless approval.status == 'approved'

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

    # safe_telegram: alert failure must never affect execution state reporting.
    def self.notify(approval, text)
      Games::TelegramNotifier.send_to_cashout_group(text, account: approval.account)
    rescue StandardError => e
      Rails.logger.error("[AutoResume] telegram failed approval=#{approval.id}: #{e.class}: #{e.message}")
    end
  end
end
