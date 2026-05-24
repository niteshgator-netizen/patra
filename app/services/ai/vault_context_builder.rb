# frozen_string_literal: true

module Ai
  class VaultContextBuilder
    def self.for_contact(contact)
      attrs = contact.custom_attributes.to_h.stringify_keys
      rows = []

      if attrs['game_username'].present?
        game = attrs['preferred_platform'].presence || 'Game'
        rows << "Game: #{game}, Username: #{attrs['game_username']}"
      end

      if attrs['preferred_platform'].present? && attrs['game_username'].blank?
        rows << "Preferred platform: #{attrs['preferred_platform']}"
      end

      return '' if rows.empty?

      "Player credentials on file:\n#{rows.join("\n")}"
    end
  end
end
