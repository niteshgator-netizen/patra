# frozen_string_literal: true

module Patra
  # Single home for the connect / disconnect / delete / reconnect lifecycle of a
  # Patra channel (an Inbox + its Channel + the upstream provider account).
  #
  # Invariants — enforced by bin/verify_lifecycle.rb:
  #   * disconnect! NEVER destroys data. It tears down the UPSTREAM connection
  #     (Zernio: DELETE /v1/accounts/{id} stops daily billing; DirectMeta: Graph
  #     DELETE /{page}/subscribed_apps unsubscribes the page webhook), invalidates
  #     the locally-stored access token, and flips the inbox to an INACTIVE state
  #     while KEEPING every conversation and message row intact.
  #   * delete! destroys the inbox (and its cascade) ONLY when confirm: true.
  #     Without confirm it refuses and raises ConfirmationRequired.
  #   * Idempotent everywhere. Every upstream call is wrapped; an upstream failure
  #     still flips the local state to inactive and is logged — it never raises out
  #     of disconnect!. Calling disconnect! twice on the same inbox is a safe no-op.
  #
  # State lives on the channel's `additional_attributes` JSONB (Channel::Api already
  # uses it for fb_page_id / zernio_account_id), so no migration is required.
  class ChannelLifecycleService
    class Error < StandardError; end
    class ConfirmationRequired < Error; end

    STATUS_KEY = 'connection_status'
    STATUS_ACTIVE = 'active'
    STATUS_INACTIVE = 'inactive'
    DISCONNECTED_AT_KEY = 'disconnected_at'
    DISCONNECT_REASON_KEY = 'disconnect_reason'
    REAUTH_KEY = 'reauthorization_required'

    # Providers this service can tear down upstream. Anything else (native
    # Chatwoot channels) gets only the local state flip, never an upstream call.
    MANAGED_PROVIDERS = %w[zernio direct_meta].freeze

    # Stored credentials we proactively clear on disconnect so a stale token can
    # never be reused after the upstream teardown.
    INVALIDATED_TOKEN_KEYS = %w[fb_page_access_token fb_user_long_lived_token].freeze

    # Disconnect a channel WITHOUT deleting anything. Upstream teardown first
    # (best-effort), then flip the inbox inactive and invalidate its token while
    # keeping all conversations. Returns the inbox. Idempotent.
    def disconnect!(inbox, reason: 'manual')
      return inbox if inbox.nil?
      # Native channels (web widget, email, SMS…) carry the column DEFAULT
      # messaging_provider='direct_meta' but are NOT Patra-managed external
      # connections — there is nothing upstream to tear down, so no-op safely
      # instead of flipping an unrelated inbox "inactive".
      return inbox unless patra_managed?(inbox)

      teardown_upstream(inbox)
      mark_disconnected!(inbox, reason: reason)
      inbox
    end

    # Flip an inbox to inactive WITHOUT any upstream call. Used by the Zernio
    # account.disconnected webhook: Zernio already tore the account down on their
    # side, so calling back would be redundant. Merges (never replaces) the
    # channel's additional_attributes, so it is safe to call repeatedly.
    def mark_disconnected!(inbox, reason: 'manual')
      return inbox if inbox.nil?

      channel = inbox.channel
      return inbox unless channel.respond_to?(:additional_attributes)

      attrs = (channel.additional_attributes || {}).to_h.dup
      attrs[STATUS_KEY] = STATUS_INACTIVE
      attrs[DISCONNECTED_AT_KEY] = Time.current.iso8601
      attrs[DISCONNECT_REASON_KEY] = reason.to_s
      attrs[REAUTH_KEY] = true
      attrs = attrs.except(*INVALIDATED_TOKEN_KEYS)

      channel.update!(additional_attributes: attrs)
      inbox
    end

    # Flip an inbox back to active and clear the re-auth flag. Called after a
    # successful (re)connect. Best-effort: a flip failure is logged but never
    # breaks the connect flow that called us. Idempotent.
    def reactivate!(inbox)
      return inbox if inbox.nil?

      channel = inbox.channel
      return inbox unless channel.respond_to?(:additional_attributes)

      attrs = (channel.additional_attributes || {}).to_h.dup
      attrs[STATUS_KEY] = STATUS_ACTIVE
      attrs[REAUTH_KEY] = false
      attrs = attrs.except(DISCONNECTED_AT_KEY, DISCONNECT_REASON_KEY)

      channel.update!(additional_attributes: attrs)
      inbox
    rescue StandardError => e
      Rails.logger.error("[ChannelLifecycle] reactivate! inbox=#{inbox&.id} #{e.class}: #{e.message}")
      inbox
    end

    # Destroy the inbox and its full cascade (channel, conversations, messages) —
    # but ONLY when confirm: true. Without confirm it refuses, raising
    # ConfirmationRequired and touching nothing. Upstream teardown runs first so
    # billing stops / the webhook unsubscribes before the rows disappear.
    def delete!(inbox, confirm: false)
      return inbox if inbox.nil?

      unless confirm
        raise ConfirmationRequired,
              "delete! requires confirm: true — refusing to destroy inbox #{inbox.id} and its conversations"
      end

      teardown_upstream(inbox)
      inbox.destroy!
      inbox
    end

    # Return the correct re-auth URL for this inbox's provider so the caller can
    # restart OAuth. The actual inactive→active flip happens via reactivate! when
    # the OAuth round-trip completes. Returns a hash { reauth_url:, messaging_provider: }.
    def reconnect!(inbox, callback_url: nil)
      return nil if inbox.nil?

      provider = provider_for(inbox)
      {
        reauth_url: provider.connect_url(callback_url: callback_url.to_s),
        messaging_provider: inbox.messaging_provider
      }
    end

    # 'active' (default) or 'inactive'. Reads the channel's additional_attributes;
    # any channel without that column is treated as active.
    def status(inbox)
      return STATUS_INACTIVE if inbox.nil?

      channel = inbox.channel
      return STATUS_ACTIVE unless channel.respond_to?(:additional_attributes)

      (channel.additional_attributes || {})[STATUS_KEY].presence || STATUS_ACTIVE
    end

    def active?(inbox)
      status(inbox) == STATUS_ACTIVE
    end

    def disconnected?(inbox)
      status(inbox) == STATUS_INACTIVE
    end

    # True ONLY for inboxes that are genuinely Patra-managed external connections:
    # a Zernio inbox, or a direct-Meta inbox that actually carries an fb_page_id.
    # messaging_provider defaults to 'direct_meta' (null:false) for EVERY inbox —
    # including native channels (web widget, email, SMS…) — so the column alone
    # cannot distinguish a real FB bridge from a default-valued native inbox.
    def patra_managed?(inbox)
      return false if inbox.nil?
      return false unless MANAGED_PROVIDERS.include?(inbox.messaging_provider)
      return true if inbox.messaging_provider == 'zernio'

      channel_fb_page_id(inbox).present? # direct_meta must have a real page
    end

    private

    def channel_fb_page_id(inbox)
      channel = inbox.channel
      return nil unless channel.respond_to?(:additional_attributes)

      (channel.additional_attributes || {})['fb_page_id']
    end

    # Resolve the messaging provider for an inbox, raising a friendly Error for
    # native / unsupported channels instead of letting BaseProvider.for blow up.
    def provider_for(inbox)
      unless patra_managed?(inbox)
        raise Error, "Inbox #{inbox.id} is not a Patra-managed channel (provider=#{inbox.messaging_provider.inspect})"
      end

      Messaging::BaseProvider.for(inbox)
    end

    # Best-effort upstream teardown. Returns the provider result (truthy on
    # success) or false. Never raises — an upstream/network failure must NOT stop
    # the caller from flipping the local state to inactive (RULE: log it, don't 500).
    def teardown_upstream(inbox)
      return false unless patra_managed?(inbox)

      Messaging::BaseProvider.for(inbox).disconnect!
    rescue StandardError => e
      Rails.logger.error("[ChannelLifecycle] upstream teardown failed inbox=#{inbox&.id} #{e.class}: #{e.message}")
      false
    end
  end
end
