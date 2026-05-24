# frozen_string_literal: true

module Messages
  class SendScheduledJob < ApplicationJob
    queue_as :low

    def perform
      ScheduledMessage.due.find_each do |scheduled|
        next if skip_contact?(scheduled)

        conversation = scheduled.conversation
        user = scheduled.created_by_user

        Messages::MessageBuilder.new(user, conversation, { content: scheduled.content, private: false }).perform
        scheduled.update!(status: 'sent', sent_at: Time.current)
      rescue StandardError => e
        Rails.logger.error("[SendScheduledJob] id=#{scheduled.id} #{e.class}: #{e.message}")
      end
    end

    private

    def skip_contact?(scheduled)
      contact = scheduled.conversation&.contact
      return true if Contacts::BlacklistChecker.blacklisted?(contact)

      attrs = (contact&.custom_attributes || {}).stringify_keys
      attrs['opted_out'] == true
    end
  end
end
