# Outbound half of the /bot ↔ Chatwoot bridge: takes an outgoing Chatwoot
# message, looks up the contact PSID via the Chatwoot REST API, and forwards
# the text to Facebook's Send API as the page.
#
# Returns true on success and false (after logging) on any failure — the
# caller (FbReplyJob) is intentionally non-raising so a Graph error does not
# put the job into Sidekiq's retry queue.
class Facebook::SendApiService
  GRAPH_HOST = 'https://graph.facebook.com'.freeze
  GRAPH_API_VERSION = 'v18.0'.freeze
  HTTP_TIMEOUT = 10

  def initialize(conversation_id, message_content)
    @conversation_id = conversation_id
    @message_content = message_content.to_s
  end

  def call
    return false if @conversation_id.blank?
    return false if @message_content.strip.empty?

    psid = fetch_psid
    return false if psid.blank?

    deliver_to_facebook(psid)
  rescue StandardError => e
    Rails.logger.error("[FbReply] send failed conversation=#{@conversation_id} #{e.class}: #{e.message}")
    false
  end

  private

  def fetch_psid
    response = HTTParty.get(
      "#{base_url}/api/v1/accounts/#{account_id}/conversations/#{@conversation_id}",
      headers: chatwoot_headers,
      timeout: HTTP_TIMEOUT
    )

    unless response.success?
      Rails.logger.error("[FbReply] conversation lookup HTTP #{response.code} conversation=#{@conversation_id}: #{response.body}")
      return nil
    end

    psid = response.parsed_response.dig('meta', 'sender', 'identifier')
    if psid.blank?
      Rails.logger.error("[FbReply] no PSID on conversation=#{@conversation_id} (meta.sender.identifier missing)")
      return nil
    end

    psid
  end

  def deliver_to_facebook(psid)
    if page_access_token.blank?
      Rails.logger.error('[FbReply] FB_PAGE_ACCESS_TOKEN not configured — cannot deliver to Facebook')
      return false
    end

    response = HTTParty.post(
      "#{GRAPH_HOST}/#{GRAPH_API_VERSION}/me/messages",
      headers: { 'Content-Type' => 'application/json' },
      body: {
        recipient: { id: psid },
        message: { text: @message_content },
        access_token: page_access_token
      }.to_json,
      timeout: HTTP_TIMEOUT
    )

    if response.success?
      mid = response.parsed_response.is_a?(Hash) ? response.parsed_response['message_id'] : nil
      Rails.logger.info("[FbReply] delivered conversation=#{@conversation_id} psid=#{psid} fb_mid=#{mid}")
      return true
    end

    Rails.logger.error(
      "[FbReply] Graph send failed conversation=#{@conversation_id} psid=#{psid} HTTP #{response.code}: #{response.body}"
    )
    false
  end

  # ---------- Config ----------

  def chatwoot_headers
    { 'api_access_token' => ENV.fetch('CHATWOOT_BRIDGE_API_TOKEN', ''), 'Accept' => 'application/json' }
  end

  def base_url
    @base_url ||= ENV.fetch('CHATWOOT_BRIDGE_BASE_URL', 'https://patrahq.com').to_s.chomp('/')
  end

  def account_id
    @account_id ||= ENV.fetch('CHATWOOT_BRIDGE_ACCOUNT_ID', '2').to_i
  end

  def page_access_token
    ENV.fetch('FB_PAGE_ACCESS_TOKEN', '').to_s
  end
end
