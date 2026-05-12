# frozen_string_literal: true

module Payments
  class EscalationNotifier
    def initialize(account)
      @account = account
    end

    def notify_all_handles_dead(platform)
      Rails.logger.error(
        "[Payments::EscalationNotifier] ALL HANDLES DEAD for account #{@account&.id} platform #{platform}"
      )
      # TODO: Create Chatwoot Notification or send email when notification pattern is confirmed
    rescue StandardError => e
      Rails.logger.error("[Payments::EscalationNotifier] notify_all_handles_dead crashed: #{e.class}: #{e.message}")
    end
  end
end
