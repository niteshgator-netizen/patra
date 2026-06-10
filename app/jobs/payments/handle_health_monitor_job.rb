# frozen_string_literal: true

module Payments
  class HandleHealthMonitorJob < ApplicationJob
    queue_as :low

    def perform
      Account.find_each do |account|
        Payments::HandleHealthMonitor.check_all(account)
      rescue StandardError => e
        # One bad account must not kill the whole sweep.
        Rails.logger.error("[HandleHealthMonitorJob] account=#{account.id} #{e.class}: #{e.message}")
      end
    end
  end
end
