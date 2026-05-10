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
#   CHATWOOT_BRIDGE_BASE_URL   default https://patrahq.com
#   CHATWOOT_BRIDGE_ACCOUNT_ID default 2
#   CHATWOOT_BRIDGE_INBOX_ID   default 2
#   CHATWOOT_BRIDGE_API_TOKEN  required (Chatwoot user/agent api_access_token)
class Facebook::ChatwootBridgeService
  class BridgeError < StandardError; end
  class ConfigurationError < BridgeError; end

  HTTP_TIMEOUT = 10

  def initialize(messaging)
    messaging = messaging.with_indifferent_access if messaging.respond_to?(:with_indifferent_access)
    @messaging   = messaging
    @sender_id   = messaging.dig('sender', 'id').to_s
    @recipient   = messaging.dig('recipient', 'id').to_s
    @text        = messaging.dig('message', 'text').to_s
    @mid         = messaging.dig('message', 'mid').to_s
    @timestamp   = messaging['timestamp']
  end

  def perform
    raise ConfigurationError, 'CHATWOOT_BRIDGE_API_TOKEN is not configured' if api_token.blank?
    raise BridgeError, 'sender id missing on Facebook payload' if @sender_id.blank?
    raise BridgeError, 'message text missing on Facebook payload' if @text.blank?

    contact_id = ensure_contact!
    conversation_id = ensure_conversation!(contact_id)
    message_id = create_message!(conversation_id)

    Rails.logger.info(
      "[BotBridge] delivered mid=#{@mid} sender=#{@sender_id} recipient=#{@recipient} " \
      "contact=#{contact_id} conversation=#{conversation_id} message=#{message_id}"
    )

    { contact_id: contact_id, conversation_id: conversation_id, message_id: message_id }
  end

  private

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
    name = Facebook::GraphProfileService.fetch_name(@sender_id).presence || @sender_id
    response = http_post(
      "/api/v1/accounts/#{account_id}/contacts",
      body: { name: name, identifier: @sender_id }
    )

    raise BridgeError, "contact create failed HTTP #{response.code}: #{response.body}" unless response.success?

    contact = response.parsed_response.dig('payload', 'contact')
    id = contact && contact['id']
    raise BridgeError, "contact create returned no id: #{response.body}" if id.blank?

    Rails.logger.info("[BotBridge] created contact id=#{id} psid=#{@sender_id} name=#{name}")
    id
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
    open = conversations.find { |c| c['inbox_id'].to_i == inbox_id && c['status'] == 'open' }
    open && open['id']
  end

  def create_conversation!(contact_id)
    response = http_post(
      "/api/v1/accounts/#{account_id}/conversations",
      body: { inbox_id: inbox_id, contact_id: contact_id }
    )

    raise BridgeError, "conversation create failed HTTP #{response.code}: #{response.body}" unless response.success?

    id = response.parsed_response['id']
    raise BridgeError, "conversation create returned no id: #{response.body}" if id.blank?

    Rails.logger.info("[BotBridge] created conversation id=#{id} contact=#{contact_id} inbox=#{inbox_id}")
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
    @base_url ||= ENV.fetch('CHATWOOT_BRIDGE_BASE_URL', 'https://patrahq.com').to_s.chomp('/')
  end

  def account_id
    @account_id ||= ENV.fetch('CHATWOOT_BRIDGE_ACCOUNT_ID', '2').to_i
  end

  def inbox_id
    @inbox_id ||= ENV.fetch('CHATWOOT_BRIDGE_INBOX_ID', '2').to_i
  end

  def api_token
    @api_token ||= ENV.fetch('CHATWOOT_BRIDGE_API_TOKEN', '').to_s
  end
end
