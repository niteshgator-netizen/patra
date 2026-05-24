# frozen_string_literal: true

module Patra
  module Cache
    TTL = {
      dashboard_stats: 60,
      reports: 300,
      contact_profile: 30,
      game_health: 60
    }.freeze

    def self.fetch(key, type: :dashboard_stats, &block)
      Rails.cache.fetch("patra:#{key}", expires_in: TTL[type], &block)
    end

    def self.invalidate_contact(contact_id)
      Rails.cache.delete("patra:contact:#{contact_id}")
    end
  end
end
