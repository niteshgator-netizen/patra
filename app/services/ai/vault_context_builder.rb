# frozen_string_literal: true

module Ai
  class VaultContextBuilder
    # Reads the SAME custom_attribute keys the orchestrator writes:
    #   game_username_<slug>  (store_game_username)
    #   game_password_<slug>  (store_game_password)
    # and lists EVERY game the player has an account on, with username (+ password if stored),
    # so when a player asks "what's my login" Bella already has it for every game.
    def self.for_contact(contact)
      attrs = contact.custom_attributes.to_h.stringify_keys
      rows = []

      # Per-game credentials (the real source of truth).
      slugs = attrs.keys.filter_map do |k|
        k.start_with?('game_username_') ? k.sub('game_username_', '') : nil
      end.uniq

      name_by_slug = {}
      begin
        name_by_slug = Game.where(slug: slugs).pluck(:slug, :name).to_h if slugs.any?
      rescue StandardError
        name_by_slug = {}
      end

      slugs.each do |slug|
        username = attrs["game_username_#{slug}"]
        next if username.blank?

        password = attrs["game_password_#{slug}"]
        label = name_by_slug[slug].presence || slug.tr('_', ' ')
        row = "Game: #{label}, Username: #{username}"
        row += ", Password: #{password}" if password.present?
        rows << row
      end

      # Legacy single-key fallback (older contacts stored one global game_username).
      if attrs['game_username'].present? && rows.none? { |r| r.include?(attrs['game_username'].to_s) }
        game = attrs['preferred_platform'].presence || 'Game'
        rows << "Game: #{game}, Username: #{attrs['game_username']}"
      end

      if attrs['preferred_platform'].present? && rows.empty?
        rows << "Preferred platform: #{attrs['preferred_platform']}"
      end

      return '' if rows.empty?

      "Player credentials on file:\n#{rows.join("\n")}"
    end
  end
end
