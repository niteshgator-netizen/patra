# frozen_string_literal: true

# Delivers one Patra::WebhookEmitter event off the money path.
# deliver() never raises, so this job never enters a retry storm.
class Patra::WebhookEmitJob < ApplicationJob
  queue_as :low

  def perform(account_id, event, payload = {})
    account = Account.find_by(id: account_id)
    return if account.nil?

    Patra::WebhookEmitter.deliver(account: account, event: event, payload: payload)
  end
end
