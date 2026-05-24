# frozen_string_literal: true

module Twilio
  class SmsHandler
    def initialize(payload, inbox:)
      @payload = payload
      @inbox = inbox
    end

    def process
      from = @payload['From']
      body = @payload['Body']
      media_url = @payload['MediaUrl0']

      contact = ContactInboxWithContactBuilder.new({
        source_id: from,
        inbox: @inbox,
        contact_attributes: { name: from, phone_number: from }
      }).perform.contact

      conversation = contact.conversations.find_by(inbox: @inbox) ||
        Conversation.create!(account: @inbox.account, inbox: @inbox, contact: contact,
                             contact_inbox: ContactInbox.find_by(contact: contact, inbox: @inbox))

      conversation.messages.create!(
        account: @inbox.account,
        inbox: @inbox,
        content: body,
        message_type: :incoming,
        content_attributes: media_url.present? ? { media_url: media_url } : {}
      )
    end

    def self.send_outbound(inbox:, conversation:, text:)
      channel = inbox.channel
      client = Twilio::REST::Client.new(channel.account_sid, channel.auth_token)
      client.messages.create(
        from: channel.phone_number,
        to: conversation.contact_inbox.source_id,
        body: text
      )
    end
  end
end
