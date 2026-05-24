# frozen_string_literal: true

module Payments
  class HandleHealthMonitorJob < ApplicationJob
    queue_as :low

    def perform
      Account.find_each do |account|
        Payments::HandleHealthMonitor.check_all(account)
      end
    end
  end
end
