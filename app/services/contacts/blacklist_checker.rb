# frozen_string_literal: true

module Contacts
  class BlacklistChecker
    RESTRICTED_REPLY = 'your account has been restricted. contact support.'.freeze

    def self.blacklisted?(contact)
      return false unless contact

      contact.custom_attributes.to_h['blacklisted'] == true
    end

    def self.blacklist_reason(contact)
      contact&.custom_attributes.to_h['blacklist_reason'].to_s
    end

    def self.restricted_reply
      RESTRICTED_REPLY
    end
  end
end
