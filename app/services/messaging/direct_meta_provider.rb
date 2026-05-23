# frozen_string_literal: true

module Messaging
  class DirectMetaProvider < BaseProvider
    GRAPH_HOST = Facebook::PatraGraphService::GRAPH_HOST
    GRAPH_VERSION = Facebook::PatraGraphService::GRAPH_VERSION
    HTTP_TIMEOUT = Facebook::PatraGraphService::HTTP_TIMEOUT
    META_SIGNATURE_HEADER = 'X-Hub-Signature-256'
    META_SIGNATURE_PREFIX = 'sha256='

    def send_message(conversation_id:, text: nil, attachments: [])
      recipient_id = conversation_id.to_s
      raise SendError, 'conversation_id (recipient PSID) is required' if recipient_id.blank?

      token = page_access_token
      raise SendError, 'fb_page_access_token not configured for inbox' if token.blank?

      results = []
      results << deliver_text(recipient_id, text, token) if text.present?

      Array(attachments).each do |attachment|
        results << deliver_attachment(recipient_id, attachment, token)
      end

      raise SendError, 'nothing to send' if results.empty?

      results.length == 1 ? results.first : results
    rescue SendError
      raise
    rescue StandardError => e
      Rails.logger.error("[DirectMeta] send exception #{e.class}: #{e.message}")
      raise SendError, e.message
    end

    def verify_webhook(headers:, body:)
      signature = headers[META_SIGNATURE_HEADER] || headers[META_SIGNATURE_HEADER.downcase]
      return false if signature.blank?
      return false unless signature.to_s.start_with?(META_SIGNATURE_PREFIX)

      raw_body = body.to_s
      meta_app_secrets.any? do |secret|
        next false if secret.blank?

        expected = "#{META_SIGNATURE_PREFIX}#{OpenSSL::HMAC.hexdigest('SHA256', secret, raw_body)}"
        ActiveSupport::SecurityUtils.secure_compare(expected, signature.to_s)
      end
    rescue StandardError => e
      Rails.logger.error("[DirectMeta] signature verify error: #{e.message}")
      false
    end

    def parse_inbound(payload)
      payload = payload.with_indifferent_access if payload.respond_to?(:with_indifferent_access)
      messaging = payload['messaging'].presence || payload
      messaging = messaging.with_indifferent_access if messaging.respond_to?(:with_indifferent_access)

      sender = messaging['sender'].is_a?(Hash) ? messaging['sender'] : {}
      message = messaging['message'].is_a?(Hash) ? messaging['message'] : {}
      sender_id = sender['id'].to_s

      profile = fetch_sender_profile(sender_id)

      {
        provider: 'direct_meta',
        conversation_id: sender_id,
        sender_id: sender_id,
        sender_name: profile&.dig(:name).presence || sender['name'],
        text: message['text'],
        attachments: Array(message['attachments']),
        timestamp: messaging['timestamp'],
        raw: payload
      }
    end

    def connect_url(callback_url:)
      app_id = fb_app_id
      raise 'FB_APP_ID not configured' if app_id.blank?

      scopes = %w[
        pages_show_list
        pages_messaging
        pages_manage_metadata
        pages_read_engagement
        business_management
      ].join(',')

      query = {
        client_id: app_id,
        redirect_uri: callback_url,
        scope: scopes,
        response_type: 'code'
      }
      "https://www.facebook.com/#{GRAPH_VERSION}/dialog/oauth?#{query.to_query}"
    end

    def disconnect!
      page_id = fb_page_id
      token = page_access_token
      return true if page_id.blank? || token.blank?

      response = HTTParty.delete(
        "#{graph_base}/#{page_id}/subscribed_apps",
        query: { access_token: token },
        timeout: HTTP_TIMEOUT
      )
      response.success?
    rescue StandardError => e
      Rails.logger.error("[DirectMeta] disconnect error: #{e.message}")
      false
    end

    private

    def graph_base
      "#{GRAPH_HOST}/#{GRAPH_VERSION}"
    end

    def deliver_text(recipient_id, text, token)
      response = HTTParty.post(
        "#{graph_base}/me/messages",
        headers: { 'Content-Type' => 'application/json' },
        body: {
          recipient: { id: recipient_id },
          message: { text: text.to_s },
          access_token: token
        }.to_json,
        timeout: HTTP_TIMEOUT
      )

      unless response.success?
        Rails.logger.error("[DirectMeta] send failed status=#{response.code} body=#{response.body}")
        raise SendError, "Meta send failed: HTTP #{response.code}"
      end

      response.parsed_response
    end

    def deliver_attachment(recipient_id, attachment, token)
      attachment = attachment.with_indifferent_access if attachment.respond_to?(:with_indifferent_access)
      attachment_type = attachment[:type].presence || 'file'
      attachment_url = attachment.dig(:payload, :url).presence || attachment[:url]

      raise SendError, 'attachment URL missing' if attachment_url.blank?

      response = HTTParty.post(
        "#{graph_base}/me/messages",
        headers: { 'Content-Type' => 'application/json' },
        body: {
          recipient: { id: recipient_id },
          message: {
            attachment: {
              type: attachment_type,
              payload: { url: attachment_url }
            }
          },
          access_token: token
        }.to_json,
        timeout: HTTP_TIMEOUT
      )

      unless response.success?
        Rails.logger.error("[DirectMeta] attachment send failed status=#{response.code} body=#{response.body}")
        raise SendError, "Meta attachment send failed: HTTP #{response.code}"
      end

      response.parsed_response
    end

    def fetch_sender_profile(sender_id)
      return nil if sender_id.blank?

      token = page_access_token
      return nil if token.blank?

      Facebook::PatraGraphService.fetch_messenger_user_profile(
        user_id: sender_id,
        page_access_token: token
      )
    rescue StandardError => e
      Rails.logger.warn("[DirectMeta] profile lookup failed sender=#{sender_id} #{e.class}: #{e.message}")
      nil
    end

    def channel_attrs
      @channel_attrs ||= inbox.channel&.additional_attributes.to_h.with_indifferent_access
    end

    def fb_page_id
      channel_attrs['fb_page_id'].to_s
    end

    def page_access_token
      channel_attrs['fb_page_access_token'].presence || ENV.fetch('FB_PAGE_ACCESS_TOKEN', '').presence
    end

    def fb_app_id
      ENV['FB_APP_ID'].presence || GlobalConfigService.load('FB_APP_ID', '')
    end

    def meta_app_secrets
      secrets = []
      channel = inbox.channel
      if channel.respond_to?(:provider_config)
        config = channel.provider_config.to_h.with_indifferent_access
        %w[app_secret app_secret_key client_secret api_secret].each do |key|
          secrets << config[key].presence
        end
      end
      secrets << ENV['FB_APP_SECRET'].presence
      secrets << GlobalConfigService.load('FB_APP_SECRET', nil)
      secrets.compact_blank.uniq
    end
  end
end
