# frozen_string_literal: true

# MEGA2 P4 - Telegram two-way v1. Parses 'approve <id>' / 'deny <id>' typed by
# ANY member of the cashout ops group (operator ruling: no per-user allowlist;
# group membership IS the trust boundary). Approvals execute through the SAME
# path the dashboard and Approvals::AutoResume use (approve! -> model callback
# -> AutoResume), so exactly-once semantics ride the existing appr_<id>
# order_id unique index. ALL DARK behind ENV PATRA_TELEGRAM_COMMANDS='true'.
#
# Edge cases handled: unknown id, already-resolved (no-op + "already done"
# reply), malformed command (usage hint), non-command chatter (silent ignore),
# double-approve race (idempotent via AutoResume), Telegram update redelivery
# (update_id dedup, 24h).
module TelegramOps
  class CommandHandler
    COMMAND_PATTERN = %r{\A\s*/?(approve|deny)\s+#?(\d+)\s*\z}i
    COMMAND_PREFIX = %r{\A\s*/?(approve|deny)\b}i
    DEDUP_TTL_SECONDS = 24 * 60 * 60

    def self.feature_enabled?
      ENV['PATRA_TELEGRAM_COMMANDS'].to_s == 'true'
    end

    def initialize(payload)
      @payload = payload.is_a?(Hash) ? payload : {}
    end

    def process
      return unless self.class.feature_enabled?

      msg = message_hash
      return if msg.blank?

      chat_id = msg.dig('chat', 'id').to_s
      group_id = ENV['TELEGRAM_CASHOUT_GROUP_ID'].to_s
      return if group_id.blank? || chat_id != group_id

      text = msg['text'].to_s
      m = COMMAND_PATTERN.match(text)
      if m.nil?
        # Looks like a command attempt but malformed -> usage hint; anything
        # else is normal group chatter -> ignore silently.
        reply('usage: approve <id> or deny <id>') if text.match?(COMMAND_PREFIX)
        return
      end

      return if duplicate_update?

      command = m[1].downcase
      approval_id = m[2].to_i
      approval = ApprovalRequest.find_by(id: approval_id)
      if approval.nil?
        reply("no approval request ##{approval_id} found")
        return
      end

      unless approval.status == 'pending'
        reply("approval ##{approval_id} already #{approval.status} - no-op")
        return
      end

      actor = acting_user(approval)
      if actor.nil?
        reply("can't #{command} ##{approval_id} - no account user available to act as")
        return
      end

      command == 'approve' ? approve(approval, actor) : deny(approval, actor)
    rescue StandardError => e
      Rails.logger.error("[TelegramOps] process failed: #{e.class}: #{e.message}")
      reply("command hit an error (#{e.class}) - check logs, nothing may have moved")
    end

    private

    def message_hash
      raw = @payload['message'] || @payload[:message]
      return nil unless raw.is_a?(Hash)

      raw.deep_stringify_keys
    rescue StandardError
      nil
    end

    # Same execute path as dashboard + AutoResume. approve! fires the model's
    # after_update_commit (enqueues AutoResumeJob when enabled); we ALSO call
    # execute! synchronously to report the REAL result back to the group -
    # the appr_<id> order_id makes the duplicate execution a no-op.
    def approve(approval, actor)
      approval.approve!(actor)
      unless Approvals::AutoResume.enabled?
        reply("approval ##{approval.id} approved - auto-execute is OFF (PATRA_APPROVAL_AUTORESUME), execute it manually")
        return
      end

      result = Approvals::AutoResume.execute!(approval)
      if result[:ok] && result[:already]
        reply("approval ##{approval.id} approved - already executed earlier, no double-move")
      elsif result[:ok]
        reply("approval ##{approval.id} approved + EXECUTED ($#{fmt_amt(approval.amount)} #{approval.action_type})")
      elsif result[:skipped]
        reply("approval ##{approval.id} approved - NOT auto-executed (#{result[:skipped]}), handle manually")
      else
        reply("approval ##{approval.id} approved but execution FAILED: #{result[:error]} (code #{result[:code]}) - verify on the panel before any redo")
      end
    end

    # Deny marks the record rejected; the player side is the EXISTING deny
    # flow - the orchestrator's recent_generosity_rejection? check turns the
    # player's next ask into a polite decline for 24h. No money moves.
    def deny(approval, actor)
      approval.reject!(actor)
      reply("approval ##{approval.id} DENIED - nothing moves. Bella declines politely on the player's next ask (24h window).")
    end

    def acting_user(approval)
      approval.account&.account_users&.order(:id)&.first&.user || approval.requesting_user
    rescue StandardError
      approval.requesting_user
    end

    def duplicate_update?
      update_id = (@payload['update_id'] || @payload[:update_id]).to_s
      return false if update_id.blank?

      key = "patra:tgops:update:#{update_id}"
      return true if Redis::Alfred.get(key).present?

      Redis::Alfred.set(key, '1', ex: DEDUP_TTL_SECONDS)
      false
    rescue StandardError
      false
    end

    def reply(text)
      Games::TelegramNotifier.send_to_cashout_group("🤖 #{text}")
    rescue StandardError => e
      Rails.logger.error("[TelegramOps] group reply failed: #{e.class}: #{e.message}")
    end

    def fmt_amt(num)
      f = num.to_f
      f == f.to_i ? f.to_i.to_s : format('%.2f', f)
    end
  end
end
