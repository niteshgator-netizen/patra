# frozen_string_literal: true

module Contacts
  class ReEngageJob < ApplicationJob
    queue_as :low

    def perform
      Account.find_each do |account|
        reengage_days = (account.custom_attributes || {}).stringify_keys['reengage_days'].to_i
        reengage_days = 7 if reengage_days <= 0
        template = (account.custom_attributes || {}).stringify_keys['reengage_message']
        template = template.presence || 'hey! been a minute 🎰 got any new games you wanna try?'

        eligible_contacts(account, reengage_days).find_each do |contact|
          send_reengage(account, contact, template)
        end
      end
    end

    private

    def eligible_contacts(account, days)
      account.contacts
             .where('last_activity_at < ? OR last_activity_at IS NULL', days.days.ago)
             .where.not(id: recently_reengaged_ids(account))
    end

    def recently_reengaged_ids(account)
      AuditLog.where(account_id: account.id, action: 're_engage_sent')
              .where('created_at >= ?', 30.days.ago)
              .pluck(Arel.sql("metadata->>'contact_id'")).compact.map(&:to_i)
    end

    def send_reengage(account, contact, template)
      return if Contacts::BlacklistChecker.blacklisted?(contact)
      return if (contact.custom_attributes || {}).stringify_keys['opted_out'] == true
      return unless has_game_account?(contact)

      conv = contact.conversations.open.last || contact.conversations.last
      return unless conv

      Messages::MessageBuilder.new(nil, conv, { content: template, private: false }).perform
      Audit::Logger.log!(account: account, action: 're_engage_sent', target: contact, metadata: { contact_id: contact.id })
    end

    def has_game_account?(contact)
      attrs = (contact.custom_attributes || {}).stringify_keys
      attrs.keys.any? { |k| k.end_with?('_username') || k == 'game_username' }
    end
  end
end
