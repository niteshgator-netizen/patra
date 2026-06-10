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

      # Idempotency: a duplicate enqueue for the same amount inside the ask
      # window must not double-message the player.
      attrs_now = conv.additional_attributes || {}
      if attrs_now['awaiting_load_amount'].to_s == amount.to_s
        set_at = begin
          Time.parse(attrs_now['awaiting_load_set_at'].to_s)
        rescue StandardError
          nil
        end
        if set_at && set_at > 30.minutes.ago
          Rails.logger.info("[AnnounceVerifiedPaymentJob] duplicate announce skipped contact=#{contact_id} amount=#{amount}")
          return
        end
      end

      msg = "your $#{amount} payment is verified ✅ where would you like it loaded?"
      Messaging::OutboundDispatcher.send(
        inbox: conv.inbox,
        conversation: conv,
        text: msg
      )

      # Remember we asked where to load, so their game-name reply triggers the load
      attrs = conv.additional_attributes || {}
      attrs['awaiting_load_amount'] = amount
      attrs['awaiting_load_set_at'] = Time.current.iso8601
      conv.update_columns(additional_attributes: attrs)

      Rails.logger.info("[AnnounceVerifiedPaymentJob] sent verified-ask contact=#{contact_id} amount=#{amount}")
    rescue StandardError => e
      Rails.logger.error("[AnnounceVerifiedPaymentJob] #{e.class}: #{e.message}")
    end
  end
end
