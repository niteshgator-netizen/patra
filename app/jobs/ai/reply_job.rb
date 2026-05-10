# Generates an AI reply for a Chatwoot conversation, delivers it to Facebook
# via the Send API, and logs it back into the Chatwoot conversation so agents
# can see what the bot said.
#
# We log to Chatwoot with `source_id: "ai_auto"` so the inbound webhook (which
# enqueues replies via Webhooks::FbReplyJob) can identify and skip these
# self-generated messages — otherwise the message_created webhook would loop
# the reply back through the Send API a second time.
class Ai::ReplyJob < ApplicationJob
  queue_as :default

  HTTP_TIMEOUT = 10
  AI_SOURCE_ID = 'ai_auto'.freeze

  def perform(conversation_id)
    reply_text = Ai::ReplyService.new(conversation_id).call
    return if reply_text.blank?

    Facebook::SendApiService.new(conversation_id, reply_text).call
    log_to_chatwoot(conversation_id, reply_text)
  end

  private

  def log_to_chatwoot(conversation_id, content)
    response = HTTParty.post(
      "#{base_url}/api/v1/accounts/#{account_id}/conversations/#{conversation_id}/messages",
      headers: {
        'api_access_token' => ENV.fetch('CHATWOOT_BRIDGE_API_TOKEN', ''),
        'Content-Type' => 'application/json',
        'Accept' => 'application/json'
      },
      body: {
        content: content,
        message_type: 'outgoing',
        private: false,
        source_id: AI_SOURCE_ID
      }.to_json,
      timeout: HTTP_TIMEOUT
    )

    return if response.success?

    Rails.logger.error(
      "[AiReply] failed to log message to Chatwoot conversation=#{conversation_id} HTTP #{response.code}: #{response.body}"
    )
  end

  def base_url
    ENV.fetch('CHATWOOT_BRIDGE_BASE_URL', 'https://patrahq.com').to_s.chomp('/')
  end

  def account_id
    ENV.fetch('CHATWOOT_BRIDGE_ACCOUNT_ID', '2').to_i
  end
end
