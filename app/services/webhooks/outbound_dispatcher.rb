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

      deliver_with_retry(account, url, body, event)
    end

    def self.deliver_with_retry(account, url, body, event, attempts: 3)
      last_error = nil
      attempts.times do |i|
        response = HTTParty.post(
          url,
          body: body.to_json,
          headers: webhook_headers(account),
          timeout: 10
        )
        log_delivery(account, event, response.code, success: response.success?)
        return if response.success?

        last_error = "HTTP #{response.code}"
        sleep(2**i)
      rescue StandardError => e
        last_error = e.message
        sleep(2**i)
      end
      log_delivery(account, event, 0, success: false, error: last_error)
      Rails.logger.error("[Webhooks::OutboundDispatcher] event=#{event} failed after #{attempts} attempts: #{last_error}")
    end

    def self.webhook_headers(account)
      secret = (account.custom_attributes || {}).stringify_keys['webhook_secret']
      headers = { 'Content-Type' => 'application/json' }
      headers['X-Patra-Signature'] = secret if secret.present?
      headers
    end

    def self.log_delivery(account, event, status_code, success:, error: nil)
      logs = Array((account.custom_attributes || {})['webhook_logs'])
      logs << {
        event: event,
        status: status_code,
        success: success,
        error: error,
        at: Time.current.iso8601
      }
      logs = logs.last(100)
      attrs = account.custom_attributes || {}
      attrs['webhook_logs'] = logs
      account.update_column(:custom_attributes, attrs)
    rescue StandardError => e
      Rails.logger.error("[Webhooks::OutboundDispatcher] log failed: #{e.message}")
    end

    def self.webhook_url(account)
      (account.custom_attributes || {}).stringify_keys['webhook_url'].to_s.presence
    end
  end
end
