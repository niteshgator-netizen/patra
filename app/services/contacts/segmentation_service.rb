# frozen_string_literal: true

module Contacts
  class SegmentationService
    SEGMENT_TAGS = {
      'high-spender' => ->(attrs) { attrs['total_deposits_amount'].to_f > 1000 },
      'at-risk' => ->(contact, attrs) { inactive_14_days?(contact) && was_active_before?(contact) },
      'whale' => ->(contact) { single_load_over_200?(contact) },
      'frequent' => ->(attrs) { attrs['total_deposits_count'].to_i > 10 }
    }.freeze

    def self.apply!(contact)
      attrs = (contact.custom_attributes || {}).stringify_keys
      labels = contact.labels.pluck(:title)

      SEGMENT_TAGS.each do |tag, rule|
        matched = rule.arity == 1 ? rule.call(attrs) : rule.call(contact, attrs)
        labels << tag if matched && labels.exclude?(tag)
      end

      contact.update!(label_list: labels.uniq)
    end

    def self.inactive_14_days?(contact)
      last = contact.last_activity_at || contact.updated_at
      last < 14.days.ago
    end

    def self.was_active_before?(contact)
      contact.account.game_actions
             .where(contact_id: contact.id, action_type: 'load', status: 'success')
             .where('created_at < ?', 14.days.ago)
             .exists?
    end

    def self.single_load_over_200?(contact)
      contact.account.game_actions
             .where(contact_id: contact.id, action_type: 'load', status: 'success')
             .where('amount > ?', 200)
             .exists?
    end
  end
end
