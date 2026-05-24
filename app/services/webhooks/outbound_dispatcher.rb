# frozen_string_literal: true

module Webhooks
  class OutboundDispatcher
    EVENTS = %w[
      conversation.created conversation.resolved
      message.created.customer message.created.agent
      contact.created game_action.completed payment.confirmed
    ].freeze

    def self.dispatch(event, account:, payload: {})
      return unless EVENTS.include?(event)

      url = webhook_url(account)
      return if url.blank?

      body = {
        event: event,
        account_id: account.id,
        timestamp: Time.current.iso8601,
        data: payload
      }

      HTTParty.post(url, body: body.to_json, headers: { 'Content-Type' => 'application/json' }, timeout: 10)
    rescue StandardError => e
      Rails.logger.error("[Webhooks::OutboundDispatcher] event=#{event} #{e.class}: #{e.message}")
    end

    def self.webhook_url(account)
      (account.custom_attributes || {}).stringify_keys['webhook_url'].to_s.presence
    end
  end
end
