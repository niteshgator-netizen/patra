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

  def initialize(conversation_id, message_content, account_id: nil)
    @conversation_id = conversation_id
    @message_content = message_content.to_s
    @account_id_override = account_id
  end

  def call
    return false if @conversation_id.blank?
    return false if @message_content.strip.empty?

    convo = fetch_conversation_payload
    return false if convo.blank?

    @inbox_id = convo['inbox_id']
    psid = convo.dig('meta', 'sender', 'identifier')
    if psid.blank?
      Rails.logger.error("[FbReply] no PSID on conversation=#{@conversation_id} (meta.sender.identifier missing)")
      return false
    end

    deliver_to_facebook(psid)
  rescue StandardError => e
    Rails.logger.error("[FbReply] send failed conversation=#{@conversation_id} #{e.class}: #{e.message}")
    false
  end

  private

  def fetch_conversation_payload
    response = HTTParty.get(
      "#{base_url}/api/v1/accounts/#{account_id}/conversations/#{@conversation_id}",
      headers: chatwoot_headers,
      timeout: HTTP_TIMEOUT
    )

    unless response.success?
      Rails.logger.error("[FbReply] conversation lookup HTTP #{response.code} conversation=#{@conversation_id}: #{response.body}")
      return nil
    end

    response.parsed_response
  end

  def deliver_to_facebook(psid)
    if page_access_token.blank?
      Rails.logger.error('[FbReply] FB_PAGE_ACCESS_TOKEN not configured — cannot deliver to Facebook')
      return false
    end

    # Show typing dots then pause proportionally to the reply length, so the
    # message lands at a human-feeling cadence rather than instantly. Typing
    # indicator is best-effort — a failure there shouldn't block the send.
    send_typing_indicator(psid)
    sleep(typing_delay_seconds)

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

  def send_typing_indicator(psid)
    response = HTTParty.post(
      "#{GRAPH_HOST}/#{GRAPH_API_VERSION}/me/messages",
      headers: { 'Content-Type' => 'application/json' },
      body: {
        recipient: { id: psid },
        sender_action: 'typing_on',
        access_token: page_access_token
      }.to_json,
      timeout: HTTP_TIMEOUT
    )

    return if response.success?

    Rails.logger.warn("[FbReply] typing_on HTTP #{response.code} psid=#{psid}: #{response.body}")
  rescue StandardError => e
    Rails.logger.warn("[FbReply] typing_on error psid=#{psid} #{e.class}: #{e.message}")
  end

  # Tiered "typing" delay — longer messages take noticeably longer to type,
  # plus a half-to-one-and-a-half second of jitter so two replies in a row
  # don't land with the same cadence. Total range: ~2s for tiny replies up
  # to ~8.5s for long ones.
  def typing_delay_seconds
    message_length = @message_content.to_s.length
    base = case message_length
           when 0..30 then 1.5
           when 31..60 then 2.5
           when 61..100 then 4.0
           when 101..150 then 5.5
           else 7.0
           end
    base + rand(0.5..1.5)
  end

  # ---------- Config ----------

  def chatwoot_headers
    { 'api_access_token' => ENV.fetch('CHATWOOT_BRIDGE_API_TOKEN', ''), 'Accept' => 'application/json' }
  end

  def base_url
    @base_url ||= ENV.fetch('CHATWOOT_BRIDGE_BASE_URL', 'https://patrahq.com').to_s.chomp('/')
  end

  def account_id
    @account_id ||= @account_id_override.presence&.to_i ||
                     ENV.fetch('CHATWOOT_BRIDGE_ACCOUNT_ID', '2').to_i
  end

  def page_access_token
    return @page_access_token if defined?(@page_access_token)

    inbox = Inbox.find_by(id: @inbox_id) if @inbox_id.present?
    from_channel = inbox&.channel&.additional_attributes&.dig('fb_page_access_token').to_s
    @page_access_token = from_channel.presence || ENV.fetch('FB_PAGE_ACCESS_TOKEN', '').to_s
  end
end
