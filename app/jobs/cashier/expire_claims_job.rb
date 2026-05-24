# frozen_string_literal: true

module Cashier
  class ExpireClaimsJob < ApplicationJob
    queue_as :low

    def perform
      CashierClaim.expired_due.find_each do |claim|
        claim.expire!
        notify_cashiers(claim)
      end
    end

    private

    def notify_cashiers(claim)
      emoji = claim.action_type == 'load' ? '🎰' : '💰'
      message = "#{emoji} New #{claim.action_type} $#{claim.amount} on #{claim.game_slug} — claim it!"
      Games::TelegramNotifier.notify(claim.account, message) if defined?(Games::TelegramNotifier)
    end
  end
end
