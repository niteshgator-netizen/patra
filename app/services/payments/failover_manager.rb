# frozen_string_literal: true

module Payments
  class FailoverManager
    FAILURE_THRESHOLD = 3
    COOLDOWN_DURATION = 1.hour

    def initialize(handle)
      @handle = handle
    end

    def record_failure!
      return unless @handle

      @handle.failure_count = (@handle.failure_count || 0) + 1
      @handle.last_failure_at = Time.current

      if @handle.failure_count >= FAILURE_THRESHOLD
        @handle.status = 'failed'
        @handle.cooldown_until = COOLDOWN_DURATION.from_now
        Rails.logger.warn(
          "[Payments::FailoverManager] Handle #{@handle.id} (#{@handle.platform}/#{@handle.handle}) marked FAILED " \
          "after #{@handle.failure_count} failures, cooldown until #{@handle.cooldown_until}"
        )
      end

      @handle.save
    rescue StandardError => e
      Rails.logger.error("[Payments::FailoverManager] record_failure! crashed: #{e.class}: #{e.message}")
    end

    def reset!
      return unless @handle

      @handle.failure_count = 0
      @handle.last_failure_at = nil
      @handle.cooldown_until = nil
      @handle.status = 'active'
      @handle.save
    end
  end
end
