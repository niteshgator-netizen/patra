# frozen_string_literal: true

module Instagram
  class MessageHandler
    def initialize(payload)
      @payload = payload
    end

    def process
      entry = @payload.dig('entry', 0)
      return unless entry

      messaging = entry.dig('messaging', 0) || entry.dig('standby', 0)
      return unless messaging

      sender_id = messaging.dig('sender', 'id')
      message = messaging['message']
      return unless sender_id && message

      handle_message(sender_id, message, messaging)
    end

    def self.send_outbound(inbox:, conversation:, text:)
      channel = inbox.channel
      recipient_id = conversation.contact_inbox.source_id
      HTTParty.post(
        "https://graph.facebook.com/v19.0/me/messages",
        body: {
          recipient: { id: recipient_id },
          message: { text: text },
          access_token: channel.access_token
        }.to_json,
        headers: { 'Content-Type' => 'application/json' }
      )
    end

    private

    def handle_message(sender_id, message, _messaging)
      text = message['text']
      attachments = message['attachments'] || []
      Rails.logger.info("[Instagram::MessageHandler] sender=#{sender_id} text=#{text&.truncate(50)} attachments=#{attachments.size}")
    end
  end
end
