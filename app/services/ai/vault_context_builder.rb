# frozen_string_literal: true

module Ai
  class VaultContextBuilder
    # Reads the SAME custom_attribute keys the orchestrator writes:
    #   game_username_<slug> / game_password_<slug>
    # Lists every game the player has an account on, deduping slug CASING
    # (e.g. 'Juwa' + 'juwa' -> one row), preferring the entry that has a password.
    # Display-dedupe only — never mutates custom_attribute data.
    def self.for_contact(contact)
      attrs = contact.custom_attributes.to_h.stringify_keys

      # One candidate per username key, keyed by normalized (downcased) slug.
      by_norm = {}
      attrs.each_key do |k|
        next unless k.start_with?('game_username_')
        raw_slug = k.sub('game_username_', '')
        username = attrs[k]
        next if username.blank?

        norm = raw_slug.downcase
        password = attrs["game_password_#{raw_slug}"]
        candidate = { slug: raw_slug, norm: norm, username: username, password: password }

        existing = by_norm[norm]
        # Prefer the entry that actually has a password.
        if existing.nil? || (existing[:password].blank? && password.present?)
          by_norm[norm] = candidate
        end
      end

      norms = by_norm.keys
      name_by_norm = {}
      begin
        if norms.any?
          Game.where('LOWER(slug) IN (?)', norms).pluck(:slug, :name).each do |slug, name|
            name_by_norm[slug.to_s.downcase] ||= name
          end
        end
      rescue StandardError
        name_by_norm = {}
      end

      rows = []
      by_norm.each_value do |c|
        label = name_by_norm[c[:norm]].presence || c[:norm].tr('_', ' ')
        row = "Game: #{label}, Username: #{c[:username]}"
        row += ", Password: #{c[:password]}" if c[:password].present?
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
