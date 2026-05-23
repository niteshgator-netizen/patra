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

    return route_via_provider_dispatcher if non_direct_meta_inbox?

    convo = fetch_conversation_payload
    return false if convo.blank?

    @inbox_id = convo['inbox_id']
    psid = convo.dig('meta', 'sender', 'identifier')
    if psid.blank?
      Rails.logger.error("[FbReply] no PSID on conversation=#{@conversation_id} (meta.sender.identifier missing)")
      return false
    end

    deliver_to_facebook(psid)
  rescue Messaging::TransientSendError
    # Re-raise so Sidekiq retries with exponential backoff. The inner
    # route_via_provider_dispatcher already logged the details.
    raise
  rescue StandardError => e
    Rails.logger.error("[FbReply] send failed conversation=#{@conversation_id} #{e.class}: #{e.message}")
    false
  end

  private

  # Looks up the AR conversation by display_id (callers pass display_id, not
  # the AR primary key). Returns true only when the inbox is configured to use
  # a non-direct-Meta provider — direct_meta inboxes fall through to the
  # existing Graph send path UNCHANGED.
  def non_direct_meta_inbox?
    @conversation_record ||= Conversation.find_by(display_id: @conversation_id, account_id: account_id)
    return false unless @conversation_record

    inbox = @conversation_record.inbox
    return false unless inbox

    @inbox_record = inbox
    inbox.messaging_provider.to_s != 'direct_meta'
  end

  def route_via_provider_dispatcher
    return false if @inbox_record.blank?

    Messaging::OutboundDispatcher.send(
      inbox: @inbox_record,
      conversation: @conversation_record,
      text: @message_content
    )
    Rails.logger.info("[FbReply] routed via #{@inbox_record.messaging_provider} provider conv=#{@conversation_id} inbox=#{@inbox_record.id}")
    true
  rescue Messaging::TransientSendError => e
    Rails.logger.warn("[FbReply] OutboundDispatcher transient error conv=#{@conversation_id} inbox=#{@inbox_record&.id}: #{e.message}; raising for Sidekiq retry")
    raise
  rescue Messaging::PermanentSendError => e
    Rails.logger.error("[FbReply] OutboundDispatcher permanent error conv=#{@conversation_id} inbox=#{@inbox_record&.id}: #{e.message}; not retrying")
    false
  rescue Messaging::SendError => e
    Rails.logger.error("[FbReply] OutboundDispatcher send failed conv=#{@conversation_id} inbox=#{@inbox_record&.id}: #{e.message}")
    false
  rescue StandardError => e
    Rails.logger.error("[FbReply] OutboundDispatcher unexpected #{e.class} conv=#{@conversation_id}: #{e.message}")
    false
  end

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

  # Tiered human-cadence delay — short reply ≈ 0.5s, long reply ≈ 2.0s.
  # Same scale as Messaging::ZernioProvider#typing_delay_seconds. Range was
  # tightened from the old 2-8.5s to keep replies feeling responsive while
  # still avoiding "lands instantly = obviously a bot" cues.
  def typing_delay_seconds
    message_length = @message_content.to_s.length
    base = case message_length
           when 0..30 then 0.5
           when 31..60 then 1.0
           when 61..100 then 1.4
           else 1.7
           end
    base + rand(0.0..0.3)
  end

  # ---------- Config ----------

  def chatwoot_headers
    { 'api_access_token' => ENV.fetch('CHATWOOT_BRIDGE_API_TOKEN', ''), 'Accept' => 'application/json' }
  end

  def base_url
    @base_url ||= ENV.fetch('CHATWOOT_BRIDGE_BASE_URL', 'http://chatwoot.railway.internal:3000').to_s.chomp('/')
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
