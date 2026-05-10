# Generates a draft reply for a Chatwoot conversation using the Anthropic
# Messages API. Returns the reply text on success, or nil when:
#   - the conversation carries the `ai-off` label (opt-out)
#   - the message history can't be fetched
#   - no usable history exists
#   - the Anthropic call fails for any reason
#
# Configuration (all read at call time):
#   ANTHROPIC_API_KEY            — required
#   CHATWOOT_BRIDGE_API_TOKEN    — required (to read conversation + messages)
#   CHATWOOT_BRIDGE_BASE_URL     — defaults to https://patrahq.com
#   CHATWOOT_BRIDGE_ACCOUNT_ID   — defaults to 2
class Ai::ReplyService
  ANTHROPIC_URL = 'https://api.anthropic.com/v1/messages'.freeze
  ANTHROPIC_VERSION = '2023-06-01'.freeze
  MODEL = 'claude-sonnet-4-6'.freeze
  MAX_TOKENS = 500
  HISTORY_LIMIT = 10
  HTTP_TIMEOUT = 30
  SKIP_LABEL = 'ai-off'.freeze
  SYSTEM_PROMPT = 'You are a helpful customer support assistant. Reply naturally and conversationally like a human. Be friendly and concise. Never mention you are an AI.'.freeze

  def initialize(conversation_id)
    @conversation_id = conversation_id
  end

  def call
    return nil if @conversation_id.blank?
    return log_and_nil('ANTHROPIC_API_KEY not configured') if api_key.blank?
    return log_and_nil('CHATWOOT_BRIDGE_API_TOKEN not configured') if chatwoot_token.blank?

    if ai_disabled?
      Rails.logger.info("[AiReply] skipping conversation=#{@conversation_id} (label='#{SKIP_LABEL}')")
      return nil
    end

    messages = build_messages
    return log_and_nil("no usable history conversation=#{@conversation_id}") if messages.empty?

    reply = invoke_anthropic(messages)
    return nil if reply.blank?

    Rails.logger.info("[AiReply] drafted conversation=#{@conversation_id} chars=#{reply.length}")
    reply
  rescue StandardError => e
    Rails.logger.error("[AiReply] failed conversation=#{@conversation_id} #{e.class}: #{e.message}")
    nil
  end

  private

  # ---------- Conversation context ----------

  def ai_disabled?
    response = HTTParty.get(
      "#{base_url}/api/v1/accounts/#{account_id}/conversations/#{@conversation_id}",
      headers: chatwoot_headers,
      timeout: HTTP_TIMEOUT
    )

    unless response.success?
      Rails.logger.warn("[AiReply] conversation lookup HTTP #{response.code} conversation=#{@conversation_id}: #{response.body}")
      return false
    end

    labels = Array(response.parsed_response['labels']).map(&:to_s)
    labels.include?(SKIP_LABEL)
  end

  def build_messages
    response = HTTParty.get(
      "#{base_url}/api/v1/accounts/#{account_id}/conversations/#{@conversation_id}/messages",
      headers: chatwoot_headers,
      timeout: HTTP_TIMEOUT
    )

    unless response.success?
      Rails.logger.error("[AiReply] message list HTTP #{response.code} conversation=#{@conversation_id}: #{response.body}")
      return []
    end

    payload = Array(response.parsed_response['payload'])
    history = payload
              .select { |m| %w[incoming outgoing].include?(m['message_type'].to_s) }
              .reject { |m| m['content'].to_s.strip.empty? }
              .sort_by { |m| m['created_at'].to_i }
              .last(HISTORY_LIMIT)
              .map { |m| { 'role' => m['message_type'].to_s == 'incoming' ? 'user' : 'assistant', 'content' => m['content'].to_s } }

    # Anthropic requires the first message to be `user`. Drop any leading
    # assistant turns so the API doesn't 400 with a role-ordering error.
    history.shift while history.any? && history.first['role'] != 'user'
    history
  end

  # ---------- Anthropic ----------

  def invoke_anthropic(messages)
    response = HTTParty.post(
      ANTHROPIC_URL,
      headers: {
        'x-api-key' => api_key,
        'anthropic-version' => ANTHROPIC_VERSION,
        'content-type' => 'application/json'
      },
      body: {
        model: MODEL,
        max_tokens: MAX_TOKENS,
        system: SYSTEM_PROMPT,
        messages: messages
      }.to_json,
      timeout: HTTP_TIMEOUT
    )

    unless response.success?
      Rails.logger.error("[AiReply] Anthropic HTTP #{response.code} conversation=#{@conversation_id}: #{response.body}")
      return nil
    end

    text = response.parsed_response.dig('content', 0, 'text')
    if text.blank?
      Rails.logger.warn("[AiReply] Anthropic returned no text conversation=#{@conversation_id} body=#{response.body}")
      return nil
    end

    text
  end

  # ---------- Helpers / config ----------

  def log_and_nil(message)
    Rails.logger.warn("[AiReply] #{message}")
    nil
  end

  def chatwoot_headers
    { 'api_access_token' => chatwoot_token, 'Accept' => 'application/json' }
  end

  def chatwoot_token
    ENV.fetch('CHATWOOT_BRIDGE_API_TOKEN', '').to_s
  end

  def api_key
    ENV.fetch('ANTHROPIC_API_KEY', '').to_s
  end

  def base_url
    @base_url ||= ENV.fetch('CHATWOOT_BRIDGE_BASE_URL', 'https://patrahq.com').to_s.chomp('/')
  end

  def account_id
    @account_id ||= ENV.fetch('CHATWOOT_BRIDGE_ACCOUNT_ID', '2').to_i
  end
end
