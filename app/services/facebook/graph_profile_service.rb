# Looks up a Facebook Messenger user's display name and profile picture from the
# Graph API using the page access token.
#
# Never raise or block message delivery: if Graph lookup fails for any reason
# (missing `pages_messaging` permission, user hasn't interacted with the page,
# expired token, network issues, etc.), we fall back to a deterministic
# "Player XXXX" display name derived from the PSID's last 4 digits.
class Facebook::GraphProfileService
  GRAPH_HOST = 'https://graph.facebook.com'.freeze
  GRAPH_VERSION = 'v18.0'.freeze
  TIMEOUT = 5

  def self.fetch_name(psid, page_access_token: nil)
    new(psid, page_access_token: page_access_token).fetch_name
  end

  def self.fetch_profile(psid, page_access_token: nil)
    new(psid, page_access_token: page_access_token).fetch_profile
  end

  def initialize(psid, page_access_token: nil)
    @psid = psid.to_s
    @page_access_token_override = page_access_token
  end

  def fetch_name
    fetch_profile[:name]
  end

  def fetch_profile
    return empty_profile if @psid.blank?

    if access_token.blank?
      Rails.logger.warn("[BotBridge] Graph profile lookup skipped (missing FB_PAGE_ACCESS_TOKEN) psid=#{@psid}")
      return fallback_profile
    end

    # Messenger PSIDs should be queried with the *page access token*:
    # GET /v18.0/{psid}?fields=name,profile_pic&access_token={PAGE_ACCESS_TOKEN}
    #
    # Some installs may not return the `name` field; fall back to first/last.
    response1 = fetch_profile_via_graph(
      fields: 'name,profile_pic',
      access_token: access_token
    )

    profile = profile_from_response(response1)
    return with_fallback_name(profile) if profile[:name].present? || profile[:profile_pic].present?

    response2 = fetch_profile_via_graph(
      fields: 'first_name,last_name,profile_pic',
      access_token: access_token
    )

    profile2 = profile_from_response(response2, fallback_name: true)
    return with_fallback_name(profile2) if profile2[:name].present? || profile2[:profile_pic].present?

    Rails.logger.warn(
      "[BotBridge] Graph profile lookup failed psid=#{@psid} both_attempts=true " \
      "http1=#{response1&.code} http2=#{response2&.code}"
    )
    fallback_profile
  rescue StandardError => e
    Rails.logger.warn("[BotBridge] Graph profile lookup error psid=#{@psid} #{e.class}: #{e.message}")
    fallback_profile
  end

  private

  def empty_profile
    { name: nil, profile_pic: nil }
  end

  def fallback_profile
    { name: player_name, profile_pic: nil }
  end

  def with_fallback_name(profile)
    return fallback_profile if profile.blank?

    profile = profile.dup
    profile[:name] = player_name if profile[:name].blank?
    profile
  end

  def player_name
    "Player #{@psid.to_s.last(4)}"
  end

  def fetch_profile_via_graph(fields:, access_token:)
    HTTParty.get(
      "#{GRAPH_HOST}/#{GRAPH_VERSION}/#{@psid}",
      query: { fields: fields, access_token: access_token },
      timeout: TIMEOUT
    )
  end

  def profile_from_response(response, fallback_name: false)
    return {} unless response&.success?

    parsed = response.parsed_response
    return {} unless parsed.is_a?(Hash)

    if parsed['name'].present?
      { name: parsed['name'].presence, profile_pic: profile_pic_url(parsed['profile_pic']) }
    else
      first = parsed['first_name'].presence
      last = parsed['last_name'].presence
      built_name = [first, last].compact.join(' ').presence
      built_name = player_name if fallback_name && built_name.blank?
      { name: built_name, profile_pic: profile_pic_url(parsed['profile_pic']) }
    end
  rescue StandardError
    {}
  end

  # Graph may return a URL string or (for `picture`) a nested hash; `profile_pic` is
  # typically a string URL for Messenger-scoped users.
  def profile_pic_url(value)
    case value
    when String
      value.presence
    when Hash
      value['url'].presence || value[:url].presence ||
        (data_hash = value['data'] || value[:data]).is_a?(Hash) && (
          data_hash['url'].presence || data_hash[:url].presence
        )
    else
      nil
    end
  end

  def access_token
    @access_token ||= @page_access_token_override.presence || ENV.fetch('FB_PAGE_ACCESS_TOKEN', '').to_s
  end
end
