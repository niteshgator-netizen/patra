# Looks up a Facebook user's display name and profile picture from the Graph API
# using the page access token. Returns empty values on any failure so the caller
# can fall back — we never want a Graph API hiccup to block message ingestion.
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
    return empty_profile if @psid.blank? || access_token.blank?

    response = HTTParty.get(
      "#{GRAPH_HOST}/#{GRAPH_VERSION}/#{@psid}",
      query: { fields: 'name,profile_pic', access_token: access_token },
      timeout: TIMEOUT
    )

    unless response.success?
      Rails.logger.warn(
        "[BotBridge] Graph profile lookup failed psid=#{@psid} http=#{response.code} body=#{response.body}"
      )
      return empty_profile
    end

    parsed = response.parsed_response
    return empty_profile unless parsed.is_a?(Hash)

    { name: parsed['name'].presence, profile_pic: profile_pic_url(parsed['profile_pic']) }
  rescue StandardError => e
    Rails.logger.warn("[BotBridge] Graph profile lookup error psid=#{@psid} #{e.class}: #{e.message}")
    empty_profile
  end

  private

  def empty_profile
    { name: nil, profile_pic: nil }
  end

  # Graph may return a URL string or (for `picture`) a nested hash; `profile_pic` is
  # typically a string URL for Messenger-scoped users.
  def profile_pic_url(value)
    case value
    when String
      value.presence
    when Hash
      value['url'].presence || value[:url].presence
    else
      nil
    end
  end

  def access_token
    @access_token ||= @page_access_token_override.presence || ENV.fetch('FB_PAGE_ACCESS_TOKEN', '').to_s
  end
end
