# frozen_string_literal: true

module Payments
  class AnnounceVerifiedPaymentJob < ApplicationJob
    queue_as :default

    def perform(account_id, contact_id, conversation_display_id, amount)
      account = Account.find_by(id: account_id)
      return unless account

      contact = account.contacts.find_by(id: contact_id)
      return unless contact

      conv = account.conversations.find_by(display_id: conversation_display_id)
      return unless conv

      msg = "your $#{amount} payment is verified ✅ where would you like it loaded?"
      Messaging::OutboundDispatcher.send(
        inbox: conv.inbox,
        conversation: conv,
        text: msg
      )
      Rails.logger.info("[AnnounceVerifiedPaymentJob] sent verified-ask contact=#{contact_id} amount=#{amount}")
    rescue StandardError => e
      Rails.logger.error("[AnnounceVerifiedPaymentJob] #{e.class}: #{e.message}")
    end
  end
end
