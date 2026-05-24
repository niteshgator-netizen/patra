# frozen_string_literal: true

module Contacts
  class LifecycleCalculator
    STAGES = %w[new engaged active vip churned].freeze

    def self.calculate(contact)
      attrs = (contact.custom_attributes || {}).stringify_keys
      return 'churned' if inactive_30_days?(contact)
      return 'vip' if attrs['total_deposits_amount'].to_f > 500 || attrs['total_deposits'].to_f > 500
      return 'active' if loaded_in_last_7_days?(contact)
      return 'engaged' if has_game_account?(attrs)
      return 'new' if contact.created_at >= 7.days.ago

      'engaged'
    end

    def self.inactive_30_days?(contact)
      last = contact.last_activity_at || contact.updated_at
      last < 30.days.ago
    end

    def self.loaded_in_last_7_days?(contact)
      contact.account.game_actions
             .where(contact_id: contact.id, action_type: 'load', status: 'success')
             .where('created_at >= ?', 7.days.ago)
             .exists?
    end

    def self.has_game_account?(attrs)
      attrs.keys.any? { |k| k.end_with?('_username') || k == 'game_username' }
    end
  end
end
