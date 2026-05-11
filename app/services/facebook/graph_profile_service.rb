# Looks up a Facebook user's display name from the Graph API using the page
# access token. Returns nil on any failure so the caller can fall back to the
# raw PSID — we never want a Graph API hiccup to block message ingestion.
class Facebook::GraphProfileService
  GRAPH_HOST = 'https://graph.facebook.com'.freeze
  TIMEOUT = 5

  def self.fetch_name(psid, page_access_token: nil)
    new(psid, page_access_token: page_access_token).fetch_name
  end

  def initialize(psid, page_access_token: nil)
    @psid = psid.to_s
    @page_access_token_override = page_access_token
  end

  def fetch_name
    return nil if @psid.blank? || access_token.blank?

    response = HTTParty.get(
      "#{GRAPH_HOST}/#{@psid}",
      query: { fields: 'name', access_token: access_token },
      timeout: TIMEOUT
    )

    unless response.success?
      Rails.logger.warn("[BotBridge] Graph profile lookup failed psid=#{@psid} http=#{response.code} body=#{response.body}")
      return nil
    end

    name = response.parsed_response.is_a?(Hash) ? response.parsed_response['name'] : nil
    name.presence
  rescue StandardError => e
    Rails.logger.warn("[BotBridge] Graph profile lookup error psid=#{@psid} #{e.class}: #{e.message}")
    nil
  end

  private

  def access_token
    @access_token ||= @page_access_token_override.presence || ENV.fetch('FB_PAGE_ACCESS_TOKEN', '').to_s
  end
end
