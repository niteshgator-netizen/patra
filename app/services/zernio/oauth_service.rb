# frozen_string_literal: true

# Wraps Zernio's headless OAuth connect flow for a Patra account.
#
# Lifecycle:
#   1. ensure_profile! — create-or-reuse the Zernio profile (one per Patra account)
#   2. connect_url — get OAuth URL for a platform (facebook/instagram/whatsapp/telegram)
#   3. (Zernio redirects the user back with connection params)
#   4. complete_connect — create-or-reuse the Patra Channel::Api + Inbox for the
#      connected Zernio account
#   5. list_accounts — enumerate connected Zernio accounts for this profile
#
# Storage:
#   - Account.custom_attributes['zernio_profile_id'] — the Zernio profile id
#     (one per Patra account, reused across all channels the customer connects)
#   - Channel::Api.additional_attributes:
#       'zernio_account_id'    — the connected platform-side account on Zernio
#       'zernio_profile_id'    — for cross-reference / debugging
#       'zernio_platform'      — facebook/instagram/whatsapp/telegram (matches
#                                the Phase F.2 icon-picker key in provider.js)
#       'zernio_page_username' — optional, populated when Zernio returns it
#   - Inbox.messaging_provider = 'zernio' — the column from the Phase E
#     migration. NEVER store this inside channel.additional_attributes; the
#     dispatcher factory reads inbox.messaging_provider.
#
# HTTP client: HTTParty (matches Messaging::ZernioProvider). Path prefixes
# never repeat /v1 because ZERNIO_BASE already includes it.
module Zernio
  class OauthService
    ZERNIO_BASE = 'https://zernio.com/api/v1'
    HTTP_TIMEOUT = 15

    SUPPORTED_PLATFORMS = %w[facebook instagram whatsapp telegram].freeze

    def initialize(account)
      @account = account
    end

    # Idempotent — returns the existing Zernio profile id if already created,
    # otherwise POSTs to /profiles and stores the result on Account.custom_attributes.
    def ensure_profile!
      existing = @account.custom_attributes&.dig('zernio_profile_id').to_s.presence
      return existing if existing

      resp = zernio_post('/profiles', {
                           name: @account.name.presence || "Patra Account #{@account.id}",
                           description: "Auto-created by Patra for account #{@account.id}"
                         })

      profile_id = resp.dig('profile', '_id').presence ||
                   resp.dig('profile', 'id').presence ||
                   resp['_id'].presence ||
                   resp['id'].presence
      raise 'Zernio /profiles returned no profile id' if profile_id.blank?

      attrs = @account.custom_attributes.to_h
      attrs['zernio_profile_id'] = profile_id
      @account.update!(custom_attributes: attrs)

      Rails.logger.info("[Zernio::Oauth] created zernio_profile_id=#{profile_id} for account=#{@account.id}")
      profile_id
    end

    # Returns { auth_url:, state:, zernio_profile_id: }. Frontend redirects
    # the user to auth_url; Zernio handles the OAuth dance and redirects back
    # to redirect_url with the connected account params.
    def connect_url(platform:, redirect_url:)
      raise ArgumentError, 'platform required' if platform.blank?
      raise ArgumentError, 'redirect_url required' if redirect_url.blank?
      raise ArgumentError, "unsupported platform: #{platform.inspect}" unless SUPPORTED_PLATFORMS.include?(platform.to_s)

      profile_id = ensure_profile!

      resp = zernio_get("/connect/#{platform}", {
                          profileId: profile_id,
                          redirect_url: redirect_url,
                          headless: true
                        })

      {
        auth_url: resp['authUrl'].presence || resp['auth_url'],
        state: resp['state'],
        zernio_profile_id: profile_id
      }
    end

    # Find-or-create the Channel::Api + Inbox pair for a connected Zernio account.
    # Idempotent: if a channel with this zernio_account_id already exists in the
    # account, returns its inbox — closes the OAuth-callback race window
    # (multiple browser clicks, retries) so we never end up with duplicate
    # sidebar entries pointing at the same Zernio account.
    def complete_connect(platform:, zernio_account_id:, page_name:, page_username: nil)
      raise ArgumentError, 'platform required' if platform.blank?
      raise ArgumentError, 'zernio_account_id required' if zernio_account_id.blank?
      raise ArgumentError, "unsupported platform: #{platform.inspect}" unless SUPPORTED_PLATFORMS.include?(platform.to_s)

      existing_inbox = find_inbox_by_zernio_account(zernio_account_id)
      if existing_inbox
        Rails.logger.info(
          "[Zernio::Oauth] reusing existing inbox=#{existing_inbox.id} channel=#{existing_inbox.channel_id} " \
          "zernio_account_id=#{zernio_account_id}"
        )
        return existing_inbox
      end

      inbox = nil
      ActiveRecord::Base.transaction do
        channel = Channel::Api.create!(
          account_id: @account.id,
          additional_attributes: {
            'zernio_account_id' => zernio_account_id,
            'zernio_profile_id' => @account.custom_attributes&.dig('zernio_profile_id'),
            'zernio_platform' => platform.to_s,
            'zernio_page_username' => page_username
          }.compact
        )

        inbox = Inbox.create!(
          account_id: @account.id,
          channel: channel,
          name: page_name.presence || "#{platform.to_s.capitalize} #{zernio_account_id.to_s[0, 8]}",
          messaging_provider: 'zernio',
          greeting_enabled: false
        )
      end

      Rails.logger.info(
        "[Zernio::Oauth] created inbox=#{inbox.id} channel=#{inbox.channel_id} " \
        "platform=#{platform} zernio_account_id=#{zernio_account_id}"
      )

      # Best-effort history backfill — failures inside the job don't break connect.
      Zernio::SyncHistoryJob.perform_later(@account.id, inbox.id) if defined?(Zernio::SyncHistoryJob)

      inbox
    end

    # Enumerate connected Zernio accounts under this profile. Best-effort —
    # returns [] on failure so callers (settings UI) degrade gracefully.
    def list_accounts
      profile_id = @account.custom_attributes&.dig('zernio_profile_id').to_s.presence
      return [] unless profile_id

      resp = zernio_get('/accounts', { profileId: profile_id })
      Array(resp['accounts'])
    rescue StandardError => e
      Rails.logger.warn("[Zernio::Oauth] list_accounts failed account=#{@account.id}: #{e.class}: #{e.message}")
      []
    end

    private

    def find_inbox_by_zernio_account(zernio_account_id)
      Channel::Api
        .where(account_id: @account.id)
        .where("additional_attributes ->> 'zernio_account_id' = ?", zernio_account_id.to_s)
        .first
        &.inboxes
        &.first
    end

    def api_key
      ENV.fetch('ZERNIO_API_KEY') { raise 'ZERNIO_API_KEY not set in Railway env' }
    end

    def auth_headers
      {
        'Authorization' => "Bearer #{api_key}",
        'Content-Type' => 'application/json',
        'Accept' => 'application/json'
      }
    end

    def zernio_get(path, query = {})
      response = HTTParty.get(
        "#{ZERNIO_BASE}#{path}",
        headers: auth_headers,
        query: query,
        timeout: HTTP_TIMEOUT
      )
      raise_for_response!('GET', path, response) unless response.success?

      parsed = response.parsed_response
      parsed.is_a?(Hash) ? parsed : (JSON.parse(response.body.to_s) rescue {})
    end

    def zernio_post(path, body = {})
      response = HTTParty.post(
        "#{ZERNIO_BASE}#{path}",
        headers: auth_headers,
        body: body.to_json,
        timeout: HTTP_TIMEOUT
      )
      raise_for_response!('POST', path, response) unless response.success?

      parsed = response.parsed_response
      parsed.is_a?(Hash) ? parsed : (JSON.parse(response.body.to_s) rescue {})
    end

    def raise_for_response!(verb, path, response)
      Rails.logger.error(
        "[Zernio::Oauth] #{verb} #{path} HTTP #{response.code} body=#{response.body.to_s[0, 200]}"
      )
      raise "Zernio #{verb} #{path} failed: HTTP #{response.code}"
    end
  end
end
