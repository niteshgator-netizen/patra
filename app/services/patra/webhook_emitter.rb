# frozen_string_literal: true

require 'openssl'

# Outbound webhook for the Patra Business Settings "webhook_url" field.
#
# Events: payment.confirmed, load.success, load.failed, cashout.executed
# Body:   { event:, account_id:, timestamp:, payload: { ... } }
#
# Posture (money-path safe):
#   - emit() is fire-and-forget: no URL configured = zero-cost no-op; delivery
#     is enqueued on the low queue; enqueue failures are swallowed. It NEVER
#     raises and never does network I/O inline.
#   - deliver() (run by Patra::WebhookEmitJob) does the HTTP POST: 3s timeout,
#     ONE retry, every failure rescued and logged. Never raises.
#   - Optional HMAC: if account.custom_attributes['webhook_secret'] is set,
#     the request carries X-Patra-Signature = hex SHA256 HMAC of the raw body.
#     (No settings-UI field exists for the secret yet — set it via console or
#     the settings API custom_attributes until the UI grows one.)
module Patra
  class WebhookEmitter
    EVENTS = %w[payment.confirmed load.success load.failed cashout.executed].freeze
    TIMEOUT_SECONDS = 3
    MAX_ATTEMPTS = 2 # first try + one retry

    class << self
      def url_for(account)
        (account&.custom_attributes || {}).stringify_keys['webhook_url'].to_s.strip.presence
      end

      # Safe to call from anywhere, including right after money movement.
      def emit(account:, event:, payload: {})
        return false unless url_for(account)

        Patra::WebhookEmitJob.perform_later(account.id, event.to_s, plain_json(payload))
        true
      rescue StandardError => e
        Rails.logger.error("[WebhookEmitter] enqueue failed event=#{event}: #{e.class}: #{e.message}")
        false
      end

      # Synchronous delivery. Called from Patra::WebhookEmitJob.
      def deliver(account:, event:, payload: {})
        url = url_for(account)
        return { ok: false, reason: 'no_url' } unless url

        body = {
          event: event.to_s,
          account_id: account.id,
          timestamp: Time.current.iso8601,
          payload: payload
        }.to_json

        headers = { 'Content-Type' => 'application/json' }
        secret = (account.custom_attributes || {}).stringify_keys['webhook_secret'].to_s
        headers['X-Patra-Signature'] = OpenSSL::HMAC.hexdigest('SHA256', secret, body) if secret.present?

        attempts = 0
        begin
          attempts += 1
          response = HTTParty.post(url, body: body, headers: headers, timeout: TIMEOUT_SECONDS)
          { ok: response.success?, status: response.code, attempts: attempts }
        rescue StandardError => e
          retry if attempts < MAX_ATTEMPTS
          Rails.logger.warn("[WebhookEmitter] delivery failed event=#{event} account=#{account.id}: #{e.class}: #{e.message}")
          { ok: false, error: e.message, attempts: attempts }
        end
      end

      private

      # ActiveJob-safe arguments: force plain JSON types (no symbols, no AR objects).
      def plain_json(payload)
        JSON.parse(payload.to_json)
      rescue StandardError
        {}
      end
    end
  end
end
