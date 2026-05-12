# frozen_string_literal: true

module Payments
  class FailoverManager
    FAILURE_THRESHOLD = 3
    FAILURE_WINDOW    = 1.hour
    COOLDOWN_DURATION = 24.hours

    def initialize(handle)
      @handle = handle
    end

    def record_failure!(reason: nil)
      @handle.with_lock do
        recent_failures =
          if @handle.last_failure_at.present? && @handle.last_failure_at >= FAILURE_WINDOW.ago
            @handle.failure_count.to_i + 1
          else
            1
          end

        limited = recent_failures >= FAILURE_THRESHOLD
        @handle.update!(
          failure_count: recent_failures,
          last_failure_at: Time.current,
          status: (limited ? 'limited' : @handle.status),
          cooldown_until: (limited ? COOLDOWN_DURATION.from_now : @handle.cooldown_until),
          notes: append_note(@handle.notes, "[#{Time.current.iso8601}] failure: #{reason || 'unspecified'}")
        )
      end

      @handle.reload
      Rails.logger.warn(
        "[FailoverManager] handle=#{@handle.id} platform=#{@handle.platform} priority=#{@handle.priority} " \
        "failures=#{@handle.failure_count} status=#{@handle.status}"
      )

      backup = Payments::HandleSelector.new(@handle.account).pick(@handle.platform)
      if backup.nil?
        Rails.logger.error("[FailoverManager] NO_HANDLES_LEFT platform=#{@handle.platform} account=#{@handle.account.id}")
        Payments::EscalationNotifier.new(@handle.account).notify_all_handles_dead(@handle.platform)
      end

      backup
    end

    def record_success!
      @handle.update!(failure_count: 0, last_used_at: Time.current, last_failure_at: nil)
    end

    private

    def append_note(existing, line)
      [existing, line].compact.join("\n").last(2000)
    end
  end
end
