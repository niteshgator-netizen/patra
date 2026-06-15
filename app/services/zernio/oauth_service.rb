# frozen_string_literal: true

# Wraps Zernio's headless OAuth connect flow for a Patra account.
#
# Lifecycle:
#   1. ensure_profile! — create-or-reuse the Zernio profile (one per Patra account)
#   2. connect_url — get OAuth URL for a platform (see SUPPORTED_PLATFORMS)
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
#       'zernio_platform'      — Patra UI platform key (facebook/instagram/…/
#                                google_business). Used by the sidebar icon
#                                picker. May differ from the Zernio API slug
#                                when PLATFORM_API_SLUGS maps an alias.
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

    # Patra UI platform keys accepted from PatraAddChannel.vue / channels API.
    # Ads platforms (meta_ads, google_ads, …) are intentionally excluded —
    # they are disabled "Coming soon" cards on the frontend.
    SUPPORTED_PLATFORMS = %w[
      facebook instagram whatsapp telegram
      tiktok youtube linkedin twitter threads
      bluesky pinterest reddit google_business discord
    ].freeze

    # Maps Patra UI keys → Zernio GET /connect/{platform} path slugs.
    # Verified against Zernio OpenAPI (docs.zernio.com/connect/get-connect-url):
    #   facebook instagram linkedin twitter tiktok youtube threads reddit
    #   pinterest bluesky googlebusiness telegram snapchat discord whatsapp
    # Patra uses `google_business` in the UI; Zernio expects `googlebusiness`.
    # Twitter/X uses `twitter` (not `x`).
    PLATFORM_API_SLUGS = {
      'google_business' => 'googlebusiness'
    }.freeze

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

      api_platform = zernio_api_platform(platform)
      resp = zernio_get("/connect/#{api_platform}", {
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

    # ── Headless Facebook page-selection handshake ───────────────────────────
    # After Zernio redirects the browser back to /patra/connect-facebook with a
    # short-lived connect_token (+ tempToken, profileId, userProfile), Patra must
    # (1) LIST the user's Facebook pages, (2) let the user pick, then (3) SAVE
    # each chosen page to Zernio — only step (3) actually persists the upstream
    # connection. Both calls authenticate with the X-Connect-Token header
    # (NOT the API key), and the connect_token is single-flow + ~15-min lived.

    # GET /connect/facebook/select-page — list the pages this user can connect.
    # Returns an Array of page hashes ({ id, name, username, category, ... }).
    # An empty Array is a valid result (user admins no pages) — callers surface
    # the "must be an admin of at least one page" message.
    def fb_list_pages(connect_token:, temp_token:, profile_id:)
      raise ArgumentError, 'connect_token required' if connect_token.blank?
      raise ArgumentError, 'temp_token required' if temp_token.blank?
      raise ArgumentError, 'profile_id required' if profile_id.blank?

      resp = zernio_get(
        '/connect/facebook/select-page',
        { profileId: profile_id, tempToken: temp_token },
        headers: connect_headers(connect_token)
      )
      Array(resp['pages'])
    rescue ArgumentError
      raise
    rescue StandardError => e
      Rails.logger.error("[Zernio::Headless] fb_list_pages account=#{@account.id} failed: #{e.class}: #{e.message}")
      raise headless_error_message(e)
    end

    # POST /connect/facebook/select-page — persist ONE chosen page on Zernio.
    # Without this call nothing is saved upstream. user_profile is forwarded
    # as-is (the URL-decoded JSON string Zernio handed back). Returns the
    # parsed Zernio response ({ redirect_url, ... }).
    def fb_save_page(connect_token:, temp_token:, profile_id:, page_id:, user_profile:)
      raise ArgumentError, 'connect_token required' if connect_token.blank?
      raise ArgumentError, 'temp_token required' if temp_token.blank?
      raise ArgumentError, 'profile_id required' if profile_id.blank?
      raise ArgumentError, 'page_id required' if page_id.blank?

      zernio_post(
        '/connect/facebook/select-page',
        {
          profileId: profile_id,
          pageId: page_id,
          tempToken: temp_token,
          userProfile: user_profile,
          redirect_url: default_success_url
        },
        headers: connect_headers(connect_token)
      )
    rescue ArgumentError
      raise
    rescue StandardError => e
      Rails.logger.error("[Zernio::Headless] fb_save_page account=#{@account.id} page_id=#{page_id} failed: #{e.class}: #{e.message}")
      raise headless_error_message(e)
    end

    # After pages are saved on Zernio, enumerate the now-connected accounts and
    # create the matching Patra inbox for each NEW one. Idempotent: skips any
    # Zernio account that already has an inbox on this Patra account (so re-runs
    # never duplicate). Returns ONLY the inboxes created in THIS call, so callers
    # can report an accurate "connected N" count.
    def sync_connected_accounts!
      created = []
      list_accounts.each do |acct|
        zernio_account_id = acct['_id'].presence || acct['id'].presence
        next if zernio_account_id.blank?
        next if find_inbox_by_zernio_account(zernio_account_id)

        inbox = complete_connect(
          platform: 'facebook',
          zernio_account_id: zernio_account_id,
          page_name: acct['name'].presence || acct['displayName'].presence || acct['username'].presence
        )
        created << inbox if inbox
      end
      created
    end

    private

    def zernio_api_platform(platform)
      key = platform.to_s
      PLATFORM_API_SLUGS.fetch(key, key)
    end

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

    # `headers:` defaults to auth_headers (Bearer API key) so existing callers
    # are unchanged; the headless page-selection calls pass connect_headers
    # (X-Connect-Token) instead.
    def zernio_get(path, query = {}, headers: auth_headers)
      response = HTTParty.get(
        "#{ZERNIO_BASE}#{path}",
        headers: headers,
        query: query,
        timeout: HTTP_TIMEOUT
      )
      raise_for_response!('GET', path, response) unless response.success?

      parsed = response.parsed_response
      parsed.is_a?(Hash) ? parsed : (JSON.parse(response.body.to_s) rescue {})
    end

    def zernio_post(path, body = {}, headers: auth_headers)
      response = HTTParty.post(
        "#{ZERNIO_BASE}#{path}",
        headers: headers,
        body: body.to_json,
        timeout: HTTP_TIMEOUT
      )
      raise_for_response!('POST', path, response) unless response.success?

      parsed = response.parsed_response
      parsed.is_a?(Hash) ? parsed : (JSON.parse(response.body.to_s) rescue {})
    end

    # Headers for the headless page-selection handshake. Authenticates with the
    # short-lived X-Connect-Token (NOT the API key) — same token for LIST + SAVE.
    def connect_headers(token)
      {
        'X-Connect-Token' => token,
        'Content-Type' => 'application/json',
        'Accept' => 'application/json'
      }
    end

    # Where Zernio's SAVE response should point the browser, and where Patra
    # navigates the user after inboxes are created — the connected-channels list.
    def default_success_url
      "#{ENV.fetch('FRONTEND_URL', 'https://patrahq.com').to_s.chomp('/')}/app/accounts/#{@account.id}/patra/facebook-accounts"
    end

    # Map a raw Zernio/HTTP failure to a short, user-safe message. The raw HTTP
    # status + body is already logged (raise_for_response! and the
    # [Zernio::Headless] rescue), so we never leak it to the end user here.
    def headless_error_message(error)
      msg = error.message.to_s
      if msg.match?(/invalid access token/i) || msg.match?(/expired/i) ||
         msg.match?(/\bHTTP 401\b/) || msg.match?(/\bHTTP 403\b/)
        'Facebook session expired — reconnect.'
      elsif msg.match?(/no pages/i)
        'No Facebook pages found — you must be an admin of at least one page.'
      else
        'Could not complete the Facebook connection. Please try reconnecting.'
      end
    end

    def raise_for_response!(verb, path, response)
      # The full body is logged here (server-side) for debugging; the raised
      # message carries only the HTTP status so no raw upstream body can reach
      # the client through a controller's generic rescue. headless_error_message
      # maps that status (401/403) to the user-facing "session expired" copy.
      Rails.logger.error(
        "[Zernio::Oauth] #{verb} #{path} HTTP #{response.code} body=#{response.body.to_s[0, 200]}"
      )
      raise "Zernio #{verb} #{path} failed: HTTP #{response.code}"
    end
  end
end
