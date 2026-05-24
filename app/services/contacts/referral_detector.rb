# frozen_string_literal: true

module Contacts
  class ReferralDetector
    REFERRAL_PATTERN = /\b(?:my friend|referral from|referred by)\s+(.+)/i.freeze

    def self.detect_and_store!(message)
      return unless message.incoming?

      contact = message.conversation&.contact
      return unless contact

      match = message.content.to_s.match(REFERRAL_PATTERN)
      return unless match

      referrer_name = match[1].to_s.strip.split(/[,.!?]/).first.to_s.strip
      return if referrer_name.blank?

      referrer = contact.account.contacts.where('LOWER(name) = ?', referrer_name.downcase).first
      return unless referrer
      return if referrer.id == contact.id

      attrs = (contact.custom_attributes || {}).stringify_keys
      return if attrs['referred_by_contact_id'].present?

      attrs['referred_by_contact_id'] = referrer.id
      contact.update!(custom_attributes: attrs)
    end
  end
end
