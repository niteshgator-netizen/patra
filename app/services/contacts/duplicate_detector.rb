# frozen_string_literal: true

module Contacts
  class DuplicateDetector
    def self.find_duplicates(contact)
      account = contact.account
      matches = []

      if contact.phone_number.present?
        matches += account.contacts.where(phone_number: contact.phone_number).where.not(id: contact.id).to_a
      end

      if contact.email.present?
        matches += account.contacts.where(email: contact.email).where.not(id: contact.id).to_a
      end

      if contact.name.present?
        matches += account.contacts.where('LOWER(name) = ?', contact.name.downcase).where.not(id: contact.id).to_a
      end

      matches.uniq
    end

    def self.merge!(primary:, duplicate:)
      duplicate.conversations.update_all(contact_id: primary.id)
      GameAction.where(contact_id: duplicate.id).update_all(contact_id: primary.id)
      attrs = primary.custom_attributes.to_h.merge(duplicate.custom_attributes.to_h)
      primary.update!(custom_attributes: attrs)
      duplicate.destroy!
      primary
    end
  end
end
