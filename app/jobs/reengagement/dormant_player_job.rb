# frozen_string_literal: true

module Reengagement
  class DormantPlayerJob < ApplicationJob
    queue_as :scheduled_jobs

    def perform
      Account.find_each do |account|
        process_account(account)
      rescue StandardError => e
        ChatwootExceptionTracker.new(e, account: account).capture_exception
      end
    end

    private

    def process_account(account)
      stale_conversation_ids = stale_facebook_messenger_conversation_ids(account)
      return if stale_conversation_ids.blank?

      contact_ids = account.contacts
                           .where(id: Conversation.where(id: stale_conversation_ids).select(:contact_id))
                           .where("(contacts.custom_attributes->>'loyalty_tier') IS NOT NULL AND " \
                                  "LOWER(TRIM(contacts.custom_attributes->>'loyalty_tier')) <> ?", 'new')
                           .where(
                             "(contacts.custom_attributes->>'last_reengagement_date') IS NULL OR " \
                             "(contacts.custom_attributes->>'last_reengagement_date')::date < ?",
                             14.days.ago.to_date
                           )
                           .distinct
                           .pluck(:id)

      Contact.where(id: contact_ids).find_each do |contact|
        next if (contact.label_list.map(&:downcase) & SendService::BLOCKED_LABELS).any?

        result = SendService.new(contact: contact, skip_dormancy_check: false).call
        Rails.logger.info("[Reengagement] sent contact=#{contact.id} account=#{account.id}") if result[:ok]
      end
    end

    def stale_facebook_messenger_conversation_ids(account)
      Message
        .where(message_type: Message.message_types[:incoming], private: false, sender_type: 'Contact')
        .joins(conversation: :inbox)
        .where(conversations: { account_id: account.id })
        .where(inboxes: { channel_type: 'Channel::FacebookPage' })
        .where("(conversations.additional_attributes->>'type') IS DISTINCT FROM ?", 'instagram_direct_message')
        .group('messages.conversation_id')
        .having('MAX(messages.created_at) < ?', 7.days.ago)
        .having('MAX(messages.created_at) IS NOT NULL')
        .pluck(Arel.sql('messages.conversation_id'))
    end
  end
end
