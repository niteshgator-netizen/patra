# frozen_string_literal: true

module Channels
  class EmailPollJob < ApplicationJob
    queue_as :scheduled_jobs
    retry_on StandardError, wait: :polynomially_longer, attempts: 3

    def perform(inbox_id = nil)
      scope = inbox_id ? Inbox.where(id: inbox_id) : Inbox.where(channel_type: 'Channel::Email')
      scope.find_each do |inbox|
        poll_inbox(inbox)
      end
    end

    private

    def poll_inbox(inbox)
      channel = inbox.channel
      return unless channel.imap_enabled

      Mail.defaults do
        retriever_method :imap, {
          address: channel.imap_address,
          port: channel.imap_port,
          user_name: channel.imap_login,
          password: channel.imap_password,
          enable_ssl: true
        }
      end

      Mail.find(what: :last, count: 10, order: :desc).each do |mail|
        process_email(inbox, mail)
      end
    rescue StandardError => e
      Rails.logger.error("[EmailPollJob] inbox=#{inbox.id} #{e.message}")
    end

    def process_email(inbox, mail)
      from = mail.from&.first
      return unless from

      subject = mail.subject.to_s
      body = mail.body.to_s.truncate(5000)
      contact = ContactInboxWithContactBuilder.new({
        source_id: from,
        inbox: inbox,
        contact_attributes: { name: from, email: from }
      }).perform.contact

      conversation = contact.conversations.find_by(inbox: inbox) ||
        Conversation.create!(account: inbox.account, inbox: inbox, contact: contact,
                             contact_inbox: ContactInbox.find_by(contact: contact, inbox: inbox))

      conversation.messages.create!(
        account: inbox.account,
        inbox: inbox,
        content: "#{subject}\n\n#{body}",
        message_type: :incoming
      )
    end
  end
end
