# frozen_string_literal: true

module Reengagement
  class MessagePicker
    TEMPLATES = [
      'hey {username}! been a min, hows it going?',
      'yo {username} where you been? we got new bonuses 🎁',
      'miss you {username}! ready to play again?',
      '{username} the bonuses are 🔥 this week, come back?'
    ].freeze

    class << self
      def message_for(contact)
        TEMPLATES.sample.gsub('{username}', display_username(contact))
      end

      def display_username(contact)
        raw = contact.custom_attributes['game_username'].presence ||
              (contact.additional_attributes || {})['game_username'].presence ||
              contact.name.to_s.strip
        token = raw.split(/\s+/).first
        return 'there' if token.blank?

        token
      end
    end
  end
end
