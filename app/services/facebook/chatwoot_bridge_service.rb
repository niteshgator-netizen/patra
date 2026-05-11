# Pushes a single Facebook Messenger event into Chatwoot via its public REST
# API, bypassing the broken in-process FacebookPage channel pipeline.
#
# Flow per event:
#   1. Search contacts for the PSID; if absent, create one (name from Graph API).
#   2. Look for an *open* conversation on the configured inbox; reuse it,
#      otherwise open a new conversation.
#   3. Append the FB message text as an incoming message on that conversation.
#
# Configuration is read from ENV so credentials and target tenant can be
# rotated without code changes:
#   CHATWOOT_BRIDGE_BASE_URL   default http://chatwoot.railway.internal:3000 (internal service URL;
#                              set http://localhost:3000 for same-process local dev)
#   CHATWOOT_BRIDGE_ACCOUNT_ID default 2
#   CHATWOOT_BRIDGE_INBOX_ID   default 2
#   CHATWOOT_BRIDGE_API_TOKEN  required (Chatwoot user/agent api_access_token)
class Facebook::ChatwootBridgeService
  class BridgeError < StandardError; end
  class ConfigurationError < BridgeError; end

  HTTP_TIMEOUT = 10

  # Lookup-only: resolves Patra inbox from page_id and finds an existing Chatwoot contact by PSID.
  def self.find_contact_id_by_psid(psid, page_id:)
    return nil if psid.blank? || page_id.blank?

    svc = allocate
    svc.instance_variable_set(:@sender_id, psid.to_s)
    svc.instance_variable_set(:@page_id, page_id.to_s)
    svc.send(:find_contact_id)
  end

  def initialize(messaging)
    messaging = messaging.with_indifferent_access if messaging.respond_to?(:with_indifferent_access)
    @messaging = messaging
    @sender_id = messaging.dig('sender', 'id').to_s
    @recipient = messaging.dig('recipient', 'id').to_s
    @text = messaging.dig('message', 'text').to_s
    @mid = messaging.dig('message', 'mid').to_s
    @timestamp = messaging['timestamp']
    @page_id = (
      messaging['_patra_fb_page_id'] ||
      messaging[:_patra_fb_page_id] ||
      @recipient
    ).to_s
  end

  def perform
    raise ConfigurationError, 'CHATWOOT_BRIDGE_API_TOKEN is not configured' if api_token.blank?
    raise BridgeError, 'sender id missing on Facebook payload' if @sender_id.blank?
    raise BridgeError, 'message text missing on Facebook payload' if @text.blank?

    contact_id = ensure_contact!
    conversation_id = ensure_conversation!(contact_id)
    message_id = create_message!(conversation_id)

    Facebook::ContactLastActive.record!(contact_id, at: messenger_active_at)

    Rails.logger.info(
      "[BotBridge] delivered mid=#{@mid} sender=#{@sender_id} recipient=#{@recipient} " \
      "contact=#{contact_id} conversation=#{conversation_id} message=#{message_id}"
    )

    {
      contact_id: contact_id,
      conversation_id: conversation_id,
      message_id: message_id,
      account_id: account_id
    }
  end

  private

  def messenger_active_at
    return Time.current if @timestamp.blank?

    Time.zone.at(@timestamp.to_f / 1000.0)
  end

  # ---------- Contact ----------

  def ensure_contact!
    found = find_contact_id
    return found if found

    create_contact!
  end

  def find_contact_id
    response = http_get(
      "/api/v1/accounts/#{account_id}/contacts/search",
      query: { q: @sender_id, include_contacts: true }
    )

    unless response.success?
      Rails.logger.warn("[BotBridge] contact search HTTP #{response.code}: #{response.body}")
      return nil
    end

    payload = Array(response.parsed_response['payload'])
    # Prefer an exact identifier match — `q` does substring matching across
    # name/email/phone too, so we filter to be sure we got the right contact.
    exact = payload.find { |c| c['identifier'].to_s == @sender_id }
    exact && exact['id']
  end

  def create_contact!
    profile = safe_fetch_graph_profile
    name = profile[:name].presence || "Player #{@sender_id.to_s.last(4)}"
    facebook_profile = "https://facebook.com/#{@sender_id}"

    body = {
      name: name,
      identifier: @sender_id,
      custom_attributes: { facebook_profile: facebook_profile }
    }
    body[:avatar_url] = profile[:profile_pic] if profile[:profile_pic].present?

    response = http_post(
      "/api/v1/accounts/#{account_id}/contacts",
      body: body
    )

    raise BridgeError, "contact create failed HTTP #{response.code}: #{response.body}" unless response.success?

    contact = response.parsed_response.dig('payload', 'contact')
    id = contact && contact['id']
    raise BridgeError, "contact create returned no id: #{response.body}" if id.blank?

    Rails.logger.info("[BotBridge] created contact id=#{id} psid=#{@sender_id} name=#{name}")
    id
  end

  # Profile enrichment is best-effort: a Graph API failure (HTTP 400, expired
  # token, network blip, etc.) must never block contact/conversation creation.
  def safe_fetch_graph_profile
    Facebook::GraphProfileService.fetch_profile(@sender_id, page_access_token: graph_page_access_token)
  rescue StandardError => e
    Rails.logger.warn(
      "[BotBridge] Graph profile lookup raised psid=#{@sender_id} #{e.class}: #{e.message}; falling back to default name"
    )
    { name: nil, profile_pic: nil }
  end

  # ---------- Conversation ----------

  def ensure_conversation!(contact_id)
    open_id = find_open_conversation_id(contact_id)
    return open_id if open_id

    create_conversation!(contact_id)
  end

  def find_open_conversation_id(contact_id)
    response = http_get("/api/v1/accounts/#{account_id}/contacts/#{contact_id}/conversations")

    unless response.success?
      Rails.logger.warn("[BotBridge] conversation list HTTP #{response.code}: #{response.body}")
      return nil
    end

    conversations = Array(response.parsed_response['payload'])
    open = conversations.find { |c| c['inbox_id'].to_i == resolved_inbox_id && c['status'] == 'open' }
    open && open['id']
  end

  def create_conversation!(contact_id)
    response = http_post(
      "/api/v1/accounts/#{account_id}/conversations",
      body: { inbox_id: resolved_inbox_id, contact_id: contact_id }
    )

    raise BridgeError, "conversation create failed HTTP #{response.code}: #{response.body}" unless response.success?

    id = response.parsed_response['id']
    raise BridgeError, "conversation create returned no id: #{response.body}" if id.blank?

    Rails.logger.info("[BotBridge] created conversation id=#{id} contact=#{contact_id} inbox=#{resolved_inbox_id}")
    id
  end

  # ---------- Message ----------

  def create_message!(conversation_id)
    response = http_post(
      "/api/v1/accounts/#{account_id}/conversations/#{conversation_id}/messages",
      body: { content: @text, message_type: 'incoming', private: false, source_id: @mid }
    )

    raise BridgeError, "message create failed HTTP #{response.code}: #{response.body}" unless response.success?

    response.parsed_response['id']
  end

  # ---------- HTTP ----------

  def http_get(path, query: {})
    HTTParty.get(
      url_for(path),
      headers: auth_headers,
      query: query,
      timeout: HTTP_TIMEOUT
    )
  end

  def http_post(path, body:)
    HTTParty.post(
      url_for(path),
      headers: auth_headers.merge('Content-Type' => 'application/json'),
      body: body.to_json,
      timeout: HTTP_TIMEOUT
    )
  end

  def url_for(path)
    "#{base_url}#{path}"
  end

  def auth_headers
    { 'api_access_token' => api_token, 'Accept' => 'application/json' }
  end

  # ---------- Config ----------

  def base_url
    @base_url ||= ENV.fetch('CHATWOOT_BRIDGE_BASE_URL', 'http://chatwoot.railway.internal:3000').to_s.chomp('/')
  end

  def account_id
    @account_id ||= bridge_inbox&.account_id || ENV.fetch('CHATWOOT_BRIDGE_ACCOUNT_ID', '2').to_i
  end

  def resolved_inbox_id
    @resolved_inbox_id ||= bridge_inbox&.id || ENV.fetch('CHATWOOT_BRIDGE_INBOX_ID', '2').to_i
  end

  def api_token
    @api_token ||= ENV.fetch('CHATWOOT_BRIDGE_API_TOKEN', '').to_s
  end

  def bridge_inbox
    return @bridge_inbox if defined?(@bridge_inbox)

    @bridge_inbox = resolve_bridge_inbox
  end

  def resolve_bridge_inbox
    return nil if @page_id.blank?

    Inbox.where(channel_type: 'Channel::Api')
         .joins(
           'INNER JOIN channel_api ON channel_api.id = inboxes.channel_id ' \
           "AND inboxes.channel_type = 'Channel::Api'"
         )
         .find_by("channel_api.additional_attributes->>'fb_page_id' = ?", @page_id)
  end

  def graph_page_access_token
    return @graph_page_access_token if defined?(@graph_page_access_token)

    @graph_page_access_token = bridge_inbox&.channel&.additional_attributes&.dig('fb_page_access_token').presence ||
                               ENV.fetch('FB_PAGE_ACCESS_TOKEN', '').presence
  end
end
