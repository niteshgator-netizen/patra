# frozen_string_literal: true

module Automation
  class VariableResolver
    VARIABLES = %w[
      first_name last_name contact_name preferred_game loyalty_tier
      last_deposit account_balance
    ].freeze

    def self.resolve(template, contact)
      return template if template.blank? || contact.blank?

      result = template.dup
      attrs = contact.custom_attributes.to_h.stringify_keys

      replacements = {
        'first_name' => contact.name.to_s.split.first,
        'last_name' => contact.name.to_s.split[1..]&.join(' '),
        'contact_name' => contact.name,
        'preferred_game' => attrs['preferred_game'],
        'loyalty_tier' => attrs['loyalty_tier'],
        'last_deposit' => attrs['last_deposit'],
        'account_balance' => attrs['account_balance']
      }

      replacements.each do |key, value|
        result = result.gsub("{{#{key}}}", value.to_s)
      end

      result
    end
  end
end
