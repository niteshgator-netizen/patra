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

    # Patra (it8 C2) — apply the viewer's name-privacy tier to a RAW NAME STRING (not a Contact).
    # Same three states as display_name. Used where we only hold the already-serialized name
    # (e.g. a push_event_data hash) and cannot re-load the Contact. Fail-safe -> first-name/Player.
    #
    # 'contact_pii_first_name' is the explicit form of the default first-name tier (added so the
    # owner can pick first-name explicitly in the role editor); it falls through to first_name.
    def apply_tier(full, account_user)
      full = full.to_s.strip
      return HIDDEN_LABEL if full.blank?
      return full if account_user.nil? || privileged?(account_user)

      permissions = role_permissions(account_user)
      return full if permissions.include?('contact_pii_full')
      return HIDDEN_LABEL if permissions.include?('contact_pii_hidden')

      first_name(full)
    rescue StandardError
      first_name(full).presence || HIDDEN_LABEL
    end

    # Patra (it8 C2) — viewer-aware wrapper around an actor's #push_event_data. Only a Contact's
    # name is masked; User/AgentBot/etc. pass through byte-identical. Used by the REST message /
    # conversation / attachment serializers so a restricted role never receives a full surname.
    # NOTE: the ActionCable broadcast path uses Contact#push_event_data directly with no per-viewer
    # context (Chatwoot broadcasts per-account, not per-user) and is NOT covered here — documented
    # residual. Fail-safe: any error returns the raw push payload (never raises into a serializer).
    def event_data_for(actor, account_user)
      return if actor.nil?

      data = actor.push_event_data
      return data unless actor.is_a?(Contact) && data.is_a?(Hash)

      data.merge(name: apply_tier(data[:name] || data['name'], account_user))
    rescue StandardError
      actor.push_event_data
    end

    # Patra (it8 C2) — mask the embedded contact-sender name inside a Message#push_event_data hash
    # (the conversation-list last-message preview). Untouched unless sender type == 'contact'.
    def mask_message_event_data(data, account_user)
      return data unless data.is_a?(Hash)

      sender = data[:sender] || data['sender']
      return data unless sender.is_a?(Hash)
      return data unless (sender[:type] || sender['type']).to_s == 'contact'

      name_key = sender.key?(:name) ? :name : 'name'
      sender[name_key] = apply_tier(sender[name_key], account_user)
      data
    rescue StandardError
      data
    end
  end
end
