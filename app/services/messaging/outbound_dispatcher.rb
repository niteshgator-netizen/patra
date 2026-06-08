# frozen_string_literal: true

module Messaging
  class OutboundDispatcher
    def self.send(inbox:, conversation:, text:, attachments: [], messaging_type: nil, message_tag: nil)
      raise ArgumentError, 'inbox required' if inbox.blank?
      raise ArgumentError, 'conversation required' if conversation.blank?

      external_conv_id = conversation.identifier.presence ||
                         conversation.additional_attributes&.dig('external_conversation_id')

      if external_conv_id.blank?
        Rails.logger.error("[OutboundDispatcher] conv=#{conversation.id} missing external_conversation_id, cannot route")
        raise Messaging::SendError, "Conversation #{conversation.id} missing external_conversation_id"
      end

      provider = Messaging::BaseProvider.for(inbox)
      original_len = text.to_s.length
      if text.to_s.length > 2200
        text = text.to_s[0, 2180] + "\n... (message trimmed)"
        Rails.logger.warn("[OutboundDispatcher] truncated reply from #{original_len} to 2200 chars conv=#{conversation.id}")
      end
      Rails.logger.info("[OutboundDispatcher] inbox=#{inbox.id} conv=#{conversation.id} provider=#{provider.class.name} text_len=#{text.to_s.length}")

      send_opts = { conversation_id: external_conv_id, text: text, attachments: attachments }
      # Only thread the tag through when present (win-back). Normal callers pass
      # nothing -> provider is invoked exactly as before, so replies stay untagged.
      send_opts[:messaging_type] = messaging_type if messaging_type
      send_opts[:message_tag] = message_tag if message_tag
      provider.send_message(**send_opts)
    rescue Messaging::SendError => e
      Rails.logger.error("[OutboundDispatcher] send failed inbox=#{inbox.id} conv=#{conversation.id} #{e.message}")
      raise
    rescue StandardError => e
      Rails.logger.error("[OutboundDispatcher] unexpected error inbox=#{inbox.id} #{e.class}: #{e.message}")
      raise
    end
  end
end
