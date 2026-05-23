# frozen_string_literal: true

module Messaging
  class ZernioProvider < BaseProvider
    API_BASE = 'https://zernio.com/api/v1'
    HTTP_TIMEOUT = 15

    TRANSIENT_HTTP_STATUSES = [408, 429].freeze
    TRANSIENT_NETWORK_EXCEPTIONS = [
      Net::OpenTimeout, Net::ReadTimeout, Timeout::Error,
      Errno::ECONNREFUSED, Errno::ECONNRESET, Errno::EHOSTUNREACH,
      Errno::ETIMEDOUT, SocketError
    ].freeze

    def send_message(conversation_id:, text: nil, attachments: [])
      raise Messaging::PermanentSendError, 'text required' if text.blank?
      raise Messaging::PermanentSendError, 'zernio_account_id missing' if zernio_account_id.blank?

      body = { accountId: zernio_account_id, message: text }
      body[:attachments] = attachments if attachments.present?

      response = HTTParty.post(
        "#{API_BASE}/inbox/conversations/#{conversation_id}/messages",
        headers: api_headers,
        body: body.to_json,
        timeout: HTTP_TIMEOUT
      )

      raise_for_http_status!(response) unless response.success?

      JSON.parse(response.body)
    rescue Messaging::SendError
      raise
    rescue *TRANSIENT_NETWORK_EXCEPTIONS => e
      Rails.logger.error("[Zernio] transient network error inbox=#{inbox.id} #{e.class}: #{e.message}")
      raise Messaging::TransientSendError, e.message
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
      msg = payload['message'] || {}
      conv = payload['conversation'] || {}
      acct = payload['account'] || {}
      sender = msg['sender'] || {}

      {
        provider: 'zernio',
        event_id: payload['id'],
        external_message_id: msg['id'],
        platform_message_id: msg['platformMessageId'],
        conversation_id: msg['conversationId'] || conv['id'],
        platform: msg['platform'] || acct['platform'],
        direction: msg['direction'],
        sender_id: sender['id'] || conv['participantId'],
        sender_name: sender['name'] || conv['participantName'],
        text: msg['text'],
        attachments: Array(msg['attachments']),
        timestamp: msg['sentAt'] || payload['timestamp'],
        zernio_account_id: acct['id'] || acct['accountId'],
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

    # Classify HTTP error responses. 5xx and 408/429 are transient (Sidekiq
    # should retry with backoff). Other 4xx are permanent (no point retrying
    # a 401, 403, 404, 422 etc. — same input will fail the same way).
    def raise_for_http_status!(response)
      status = response.code.to_i
      Rails.logger.error("[Zernio] send failed inbox=#{inbox.id} status=#{status} body=#{response.body}")
      msg = "Zernio send failed: HTTP #{status}"

      if status >= 500 || TRANSIENT_HTTP_STATUSES.include?(status)
        raise Messaging::TransientSendError, msg
      end

      raise Messaging::PermanentSendError, msg
    end

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
      inbox.channel&.additional_attributes&.dig('zernio_account_id')
    end
  end
end
