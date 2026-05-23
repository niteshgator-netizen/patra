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
  REPLY_LOCK_KEY = 'patra:reply_lock:conv:%<conv_id>s'.freeze
  REPLY_LOCK_TTL = 30

  def perform(conversation_id, bridge_account_id = nil, fb_attachments = nil)
    @bridge_account_id = bridge_account_id

    lock_key = format(REPLY_LOCK_KEY, conv_id: conversation_id)
    already_replied = Redis::Alfred.get(lock_key)
    if already_replied
      Rails.logger.info("[AiReply] skipping duplicate reply conv=#{conversation_id}")
      return
    end
    Redis::Alfred.set(lock_key, '1', ex: REPLY_LOCK_TTL)

    reply_text = Ai::ReplyService.new(
      conversation_id,
      account_id: bridge_account_id,
      attachments: fb_attachments
    ).call
    if reply_text.blank?
      Rails.logger.info("[AiReply] job finished without sending conversation=#{conversation_id}")
      return
    end

    sent = Facebook::SendApiService.new(
      conversation_id,
      reply_text,
      account_id: effective_account_id
    ).call
    unless sent
      Rails.logger.warn("[AiReply] Facebook send failed after draft conversation=#{conversation_id}")
    end
    log_to_chatwoot(conversation_id, reply_text)
  rescue Messaging::TransientSendError => e
    # Transient outbound failure (5xx/408/429/timeout). Release the reply
    # lock so Sidekiq's retry can re-acquire and regenerate the AI draft
    # cleanly. Do NOT call log_to_chatwoot here — we don't want a failed
    # draft persisted; the retry will write the fresh draft itself.
    release_reply_lock(lock_key)
    Rails.logger.warn(
      "[AiReply] transient send error conv=#{conversation_id} released lock for Sidekiq retry: #{e.message}"
    )
    raise
  end

  private

  # Best-effort delete of the reply-lock key. A Redis error here is logged
  # and swallowed — Sidekiq will still retry the job; worst case the lock
  # naturally expires in 30 seconds and the retry takes over after that.
  def release_reply_lock(lock_key)
    return if lock_key.blank?

    Redis::Alfred.delete(lock_key)
  rescue StandardError => e
    Rails.logger.warn("[AiReply] failed to release reply lock: #{e.class}: #{e.message}")
  end

  def log_to_chatwoot(conversation_id, content)
    response = HTTParty.post(
      "#{base_url}/api/v1/accounts/#{effective_account_id}/conversations/#{conversation_id}/messages",
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
    ENV.fetch('CHATWOOT_BRIDGE_BASE_URL', 'http://chatwoot.railway.internal:3000').to_s.chomp('/')
  end

  def effective_account_id
    aid = @bridge_account_id
    aid = aid.to_i if aid.present?
    return aid if aid.present? && aid.positive?

    ENV.fetch('CHATWOOT_BRIDGE_ACCOUNT_ID', '2').to_i
  end
end
