# frozen_string_literal: true

module Webhooks
  class ZernioController < ActionController::API
    SUPPORTED_EVENTS = %w[
      message.received message.sent message.delivered
      message.read message.failed
      account.connected account.disconnected
    ].freeze

    def create
      raw_body = request.body.read

      unless verify_signature(raw_body)
        Rails.logger.warn("[ZernioWebhook] signature verification failed ip=#{request.remote_ip}")
        return head :unauthorized
      end

      payload = JSON.parse(raw_body)
      event = payload['event'].to_s

      unless SUPPORTED_EVENTS.include?(event)
        Rails.logger.info("[ZernioWebhook] unknown event=#{event} — acking")
        return head :ok
      end

      case event
      when 'message.received'
        ProcessZernioInboundJob.perform_later(payload)
      when 'message.failed'
        Rails.logger.error("[ZernioWebhook] message.failed payload=#{payload['data']&.slice('messageId', 'conversationId')}")
      else
        # message.sent / delivered / read / account.* — ack only for now
        Rails.logger.info("[ZernioWebhook] ack event=#{event}")
      end

      head :ok
    rescue JSON::ParserError => e
      Rails.logger.error("[ZernioWebhook] invalid JSON: #{e.message}")
      head :bad_request
    rescue StandardError => e
      Rails.logger.error("[ZernioWebhook] #{e.class}: #{e.message}\n#{e.backtrace.first(5).join("\n")}")
      head :internal_server_error
    end

    private

    def verify_signature(raw_body)
      signature = request.headers['X-Zernio-Signature']
      secret = ENV['ZERNIO_WEBHOOK_SECRET']
      return false if signature.blank? || secret.blank?

      expected = OpenSSL::HMAC.hexdigest('SHA256', secret, raw_body)
      ActiveSupport::SecurityUtils.secure_compare(signature.to_s, expected)
    rescue StandardError => e
      Rails.logger.error("[ZernioWebhook] signature check error: #{e.message}")
      false
    end
  end
end
