# frozen_string_literal: true

module Messaging
  class ZernioProvider < BaseProvider
    API_BASE = 'https://zernio.com/api/v1'
    HTTP_TIMEOUT = 15

    def send_message(conversation_id:, text: nil, attachments: [])
      raise Messaging::SendError, 'text required' if text.blank?
      raise Messaging::SendError, 'zernio_account_id missing' if zernio_account_id.blank?

      body = { accountId: zernio_account_id, message: text }
      body[:attachments] = attachments if attachments.present?

      response = HTTParty.post(
        "#{API_BASE}/inbox/conversations/#{conversation_id}/messages",
        headers: api_headers,
        body: body.to_json,
        timeout: HTTP_TIMEOUT
      )

      unless response.success?
        Rails.logger.error("[Zernio] send failed inbox=#{inbox.id} status=#{response.code} body=#{response.body}")
        raise Messaging::SendError, "Zernio send failed: HTTP #{response.code}"
      end

      JSON.parse(response.body)
    rescue Messaging::SendError
      raise
    rescue StandardError => e
      Rails.logger.error("[Zernio] send exception inbox=#{inbox.id} #{e.class}: #{e.message}")
      raise Messaging::SendError, e.message
    end

    def verify_webhook(headers:, body:)
      raw_sig = headers['x-zernio-signature'] || headers['X-Zernio-Signature']
      return false if raw_sig.blank?
      return false if webhook_secret.blank?

      expected = OpenSSL::HMAC.hexdigest('SHA256', webhook_secret, body.to_s)
      ActiveSupport::SecurityUtils.secure_compare(raw_sig.to_s, expected)
    rescue StandardError => e
      Rails.logger.error("[Zernio] signature verify error: #{e.message}")
      false
    end

    def parse_inbound(payload)
      data = payload['data'] || {}
      sender = data['sender'] || {}
      {
        provider: 'zernio',
        external_message_id: data['messageId'],
        conversation_id: data['conversationId'],
        platform: data['platform'],
        direction: data['direction'],
        sender_id: sender['id'],
        sender_name: sender['name'],
        text: data['text'],
        attachments: Array(data['attachments']),
        timestamp: data['timestamp'],
        raw: payload
      }
    end

    def connect_url(callback_url:)
      "https://zernio.com/oauth/connect/facebook?redirect_uri=#{CGI.escape(callback_url)}"
    end

    def disconnect!
      return true if zernio_account_id.blank?

      response = HTTParty.delete(
        "#{API_BASE}/connections/#{zernio_account_id}",
        headers: api_headers,
        timeout: HTTP_TIMEOUT
      )
      response.success?
    rescue StandardError => e
      Rails.logger.error("[Zernio] disconnect error inbox=#{inbox.id}: #{e.message}")
      false
    end

    private

    def api_headers
      {
        'Authorization' => "Bearer #{api_key}",
        'Content-Type' => 'application/json',
        'Accept' => 'application/json'
      }
    end

    def api_key
      ENV.fetch('ZERNIO_API_KEY') { raise 'ZERNIO_API_KEY not set in Railway env' }
    end

    def webhook_secret
      ENV.fetch('ZERNIO_WEBHOOK_SECRET', nil)
    end

    def zernio_account_id
      inbox.additional_attributes&.dig('zernio_account_id')
    end
  end
end
