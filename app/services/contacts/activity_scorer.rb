# frozen_string_literal: true

module Contacts
  class ActivityScorer
    WEIGHTS = {
      message_7d: 10,
      load_7d: 20,
      cashout_7d: 15,
      inactive_30d: -30
    }.freeze

    def self.score(contact)
      s = 0
      s += WEIGHTS[:message_7d] if Message.where(sender: contact).where('created_at > ?', 7.days.ago).exists?
      s += WEIGHTS[:load_7d] if GameAction.where(contact: contact, action_type: 'load', status: 'success').where('created_at > ?', 7.days.ago).exists?
      s += WEIGHTS[:cashout_7d] if GameAction.where(contact: contact, action_type: 'cashout', status: 'success').where('created_at > ?', 7.days.ago).exists?
      s += WEIGHTS[:inactive_30d] unless Message.where(sender: contact).where('created_at > ?', 30.days.ago).exists?
      s
    end

    def self.update_all(account)
      account.contacts.find_each do |contact|
        attrs = contact.custom_attributes || {}
        attrs['activity_score'] = score(contact)
        contact.update_column(:custom_attributes, attrs)
      end
    end
  end
end
