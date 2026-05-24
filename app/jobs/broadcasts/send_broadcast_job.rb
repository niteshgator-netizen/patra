# frozen_string_literal: true

module Broadcasts
  class SendBroadcastJob < ApplicationJob
    queue_as :low
    retry_on StandardError, wait: :polynomially_longer, attempts: 3

    RATE_LIMITS = { 'facebook' => 50, 'instagram' => 50, 'sms' => 100, 'email' => 200, 'whatsapp' => 50 }.freeze

    def perform(broadcast_id)
      broadcast = Broadcast.find(broadcast_id)
      broadcast.update!(status: 'sending')

      contacts = Contacts::SegmentFilter.new(broadcast.account, broadcast.segment_filter).contacts
      rate_limit = RATE_LIMITS[broadcast.channel] || 50
      sent = 0
      failed = 0

      contacts.find_each do |contact|
        next if skip_contact?(contact)

        content = Automation::VariableResolver.resolve(broadcast.content, contact)
        send_to_contact(broadcast, contact, content)
        sent += 1
        sleep(60.0 / rate_limit) if (sent % rate_limit).zero?
      rescue StandardError => e
        failed += 1
        Rails.logger.error("[SendBroadcastJob] contact=#{contact.id} #{e.message}")
      end

      broadcast.update!(status: 'sent', sent_count: sent, failed_count: failed)
      UsageRecord.increment!(account: broadcast.account, metric: 'broadcasts', quantity: sent)
    rescue StandardError => e
      broadcast&.update!(status: 'draft')
      Audit::Logger.log(action: 'job_failed', target: broadcast, metadata: { job: self.class.name, error: e.message }) if defined?(Audit::Logger)
      raise
    end

    private

    def skip_contact?(contact)
      Contacts::BlacklistChecker.blacklisted?(contact) ||
        contact.custom_attributes.to_h['opted_out'] == true
    end

    def send_to_contact(broadcast, contact, content)
      inbox = broadcast.account.inboxes.first
      return unless inbox

      conversation = contact.conversations.where(inbox: inbox).last
      unless conversation
        contact_inbox = ContactInbox.find_by(contact: contact, inbox: inbox)
        conversation = Conversation.create!(
          account: broadcast.account,
          inbox: inbox,
          contact: contact,
          contact_inbox: contact_inbox
        ) if contact_inbox
      end
      return unless conversation

      user = broadcast.created_by_user || broadcast.account.account_users.first&.user
      Messages::MessageBuilder.new(user, conversation, { content: content, private: false }).perform
    end
  end
end
