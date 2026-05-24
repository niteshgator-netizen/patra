# frozen_string_literal: true

module Payments
  class HandleHealthMonitor
    THRESHOLD = 0.5
    FAILURE_WINDOW = 24.hours

    def self.check_all(account)
      account.payment_handles.find_each do |handle|
        check_handle(handle)
      end
    end

    def self.check_handle(handle)
      stats = handle_stats(handle)
      return if stats[:total].zero?

      rate = stats[:confirmed].to_f / stats[:total]
      return if rate >= THRESHOLD

      handle.update!(status: 'disabled')
      notify_flagged(handle, stats)
    end

    def self.handle_stats(handle)
      actions = handle.account.game_actions.where(
        'created_at > ?', FAILURE_WINDOW.ago
      ).where(payment_handle: handle.handle)

      total = actions.count
      confirmed = actions.where(status: 'success').count
      { total: total, confirmed: confirmed, rate: total.zero? ? 1.0 : confirmed.to_f / total }
    end

    def self.notify_flagged(handle, stats)
      message = "⚠️ #{handle.platform} handle @#{handle.handle} flagged — #{stats[:total] - stats[:confirmed]} failures in 24h"
      Games::TelegramNotifier.notify(handle.account, message) if defined?(Games::TelegramNotifier)
    end
  end
end
