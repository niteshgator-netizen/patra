# frozen_string_literal: true

module Payments
  class EscalationNotifier
    def initialize(account)
      @account = account
    end

    def notify_all_handles_dead(platform)
      platform_label = platform.to_s.upcase
      alert = "ALL #{platform_label} HANDLES UNAVAILABLE. Add a new handle or re-enable existing ones immediately."

      @account.administrators.find_each do |admin|
        Notification.create!(
          account: @account,
          user: admin,
          notification_type: :patra_all_payment_handles_dead,
          primary_actor_type: 'Account',
          primary_actor_id: @account.id,
          meta: { 'alert' => alert, 'platform' => platform.to_s }
        )
      rescue StandardError => e
        Rails.logger.warn("[EscalationNotifier] failed for user=#{admin.id}: #{e.class} #{e.message}")
      end
    end
  end
end
