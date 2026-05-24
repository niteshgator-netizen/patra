# frozen_string_literal: true

module Conversations
  class AutoResolveJob < ApplicationJob
    queue_as :low

    def perform
      Account.find_each do |account|
        hours = auto_resolve_hours(account)
        next if hours <= 0

        stale = account.conversations.open.where('last_activity_at < ?', hours.hours.ago)
        stale.find_each do |conv|
          next if Contacts::BlacklistChecker.blacklisted?(conv.contact)

          conv.update!(status: :resolved)
          Messages::MessageBuilder.new(
            nil,
            conv,
            { content: "Auto-resolved after #{hours}h of inactivity", message_type: :activity, private: true }
          ).perform
        end
      end
    end

    private

    def auto_resolve_hours(account)
      val = (account.custom_attributes || {}).stringify_keys['auto_resolve_hours']
      val.nil? ? 24 : val.to_i
    end
  end
end
