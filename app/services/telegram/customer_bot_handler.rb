# frozen_string_literal: true

module Telegram
  class CustomerBotHandler
    def initialize(payload, inbox:)
      @payload = payload
      @inbox = inbox
    end

    def process
      message = @payload['message']
      return unless message

      chat_id = message.dig('chat', 'id')
      text = message['text'].to_s
      from = message['from']

      if text.start_with?('/start')
        handle_start(chat_id, from)
      elsif message['photo']
        handle_photo(chat_id, message['photo'])
      elsif message['document']
        handle_document(chat_id, message['document'])
      else
        handle_text(chat_id, text, from)
      end
    end

    def self.send_message(inbox:, conversation:, text:)
      token = inbox.channel.bot_token
      chat_id = conversation.contact_inbox.source_id
      HTTParty.post(
        "https://api.telegram.org/bot#{token}/sendMessage",
        body: { chat_id: chat_id, text: text }.to_json,
        headers: { 'Content-Type' => 'application/json' }
      )
    end

    private

    def handle_start(chat_id, from)
      contact = find_or_create_contact(chat_id, from)
      send_reply(chat_id, "Welcome #{contact.name}! How can we help you today?")
    end

    def handle_text(chat_id, text, from)
      find_or_create_contact(chat_id, from)
      send_reply(chat_id, 'Thanks for your message. An agent will respond shortly.')
    end

    def handle_photo(chat_id, _photos)
      send_reply(chat_id, 'Photo received. Our team will review it.')
    end

    def handle_document(chat_id, _doc)
      send_reply(chat_id, 'Document received. Our team will review it.')
    end

    def find_or_create_contact(chat_id, from)
      ContactInboxWithContactBuilder.new({
        source_id: chat_id.to_s,
        inbox: @inbox,
        contact_attributes: { name: from['first_name'] || "Telegram #{chat_id}" }
      }).perform.contact
    end

    def send_reply(chat_id, text)
      self.class.send_message(inbox: @inbox, conversation: OpenStruct.new(contact_inbox: OpenStruct.new(source_id: chat_id)), text: text)
    end
  end
end
