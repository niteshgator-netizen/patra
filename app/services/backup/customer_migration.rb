# frozen_string_literal: true

module Backup
  class CustomerMigration
    def self.migrate(account, from:, to:)
      account.contacts.find_each do |contact|
        conversation = contact.conversations.last
        next unless conversation

        user = account.account_users.first&.user
        message = "Hey! We've moved to a new page. This is still us — #{account.name}"
        Messages::MessageBuilder.new(user, conversation, { content: message, private: false }).perform
      end

      attrs = account.custom_attributes || {}
      attrs['backup_migration'] = { from_page: from.page_id, to_page: to.page_id, at: Time.current.iso8601 }
      account.update!(custom_attributes: attrs)
    end
  end
end
