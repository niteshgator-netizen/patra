# frozen_string_literal: true

module Payments
  class SmartRouter
    def self.select_handle(account, platform: nil, amount: nil)
      handles = account.payment_handles.active.order(:priority)
      handles = handles.where(platform: platform) if platform.present?
      handles = handles.reject(&:in_cooldown?)
      return nil if handles.empty?

      unhealthy = handles.select { |h| Payments::HandleHealthMonitor.handle_stats(h)[:rate] < 0.5 }
      healthy = handles - unhealthy
      pool = healthy.presence || handles

      pool.min_by { |h| usage_count(h) }.tap do |selected|
        increment_usage(selected) if selected
      end
    end

    def self.usage_count(handle)
      GameAction.where(payment_handle: handle.handle, status: 'success')
                .where('created_at > ?', 24.hours.ago).count
    end

    def self.increment_usage(_handle)
      nil
    end
  end
end
