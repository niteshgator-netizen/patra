# frozen_string_literal: true

module Usage
  class RecordJob < ApplicationJob
    queue_as :low

    def perform(account_id, metric, quantity = 1)
      account = Account.find(account_id)
      UsageRecord.increment!(account: account, metric: metric, quantity: quantity)
    end
  end
end
