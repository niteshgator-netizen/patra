# frozen_string_literal: true

# Patra (it7) — server-side name-privacy chokepoint for player (contact) names.
#
# Three states, chosen per role via custom_role permissions:
#   * owner OR administrator              -> FULL name (always)
#   * custom_role has 'contact_pii_full'  -> FULL name
#   * custom_role has 'contact_pii_hidden'-> "Player" (name fully hidden)
#   * neither pii key (DEFAULT)           -> first name only ("John Dorian" -> "John")
#   * blank contact name                  -> "Player"
#
# Pure (no Current.* dependency) and fail-safe: any error falls back to first-name-only so a full
# surname is never leaked. Used by app/views/api/v1/models/_contact.json.jbuilder.
module Patra
  module ContactPrivacy
    HIDDEN_LABEL = 'Player'

    module_function

    def display_name(contact, account_user)
      full = contact_name(contact)
      return HIDDEN_LABEL if full.blank?
      return full if account_user.nil?
      return full if privileged?(account_user)

      permissions = role_permissions(account_user)
      return full if permissions.include?('contact_pii_full')
      return HIDDEN_LABEL if permissions.include?('contact_pii_hidden')

      first_name(full)
    rescue StandardError
      first_name(contact_name(contact)).presence || HIDDEN_LABEL
    end

    # Owner OR administrator always sees the full name.
    def privileged?(account_user)
      return true if account_user.administrator?

      account_user.user&.owner_of?(account_user.account) || false
    rescue StandardError
      false
    end

    def role_permissions(account_user)
      Array(account_user.custom_role&.permissions)
    rescue StandardError
      []
    end

    def contact_name(contact)
      contact&.name.to_s.strip
    end

    def first_name(full)
      full.to_s.strip.split(/\s+/).first.to_s
    end
  end
end
