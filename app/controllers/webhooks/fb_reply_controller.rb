# Receives Chatwoot's `message_created` webhook. When an agent replies on a
# conversation in the bridged inbox, this endpoint enqueues the outbound job
# that posts the reply back to Facebook via the Send API.
#
# We acknowledge every request with 200 immediately and only enqueue the job
# when the payload represents a real outgoing public message on the bridged
# inbox — incoming events, private notes, and other inboxes are ignored.
class Webhooks::FbReplyController < ActionController::API
  skip_before_action :verify_authenticity_token, raise: false

  # POST /webhooks/fb_reply
  def receive
    enqueue_reply if eligible?
    head :ok
  rescue StandardError => e
    Rails.logger.error("[FbReply] receiver crashed: #{e.class}: #{e.message}")
    head :ok
  end

  private

  def eligible?
    inbox_id_matches? && outgoing? && !private_message? && !ai_self_message?
  end

  # Messages we logged ourselves via Ai::ReplyJob carry source_id="ai_auto".
  # Skipping them here breaks the loop: AI reply → log to Chatwoot →
  # message_created webhook → this controller → would re-send to FB.
  def ai_self_message?
    params[:source_id].to_s == 'ai_auto'
  end

  def inbox_id_matches?
    expected = ENV.fetch('CHATWOOT_BRIDGE_INBOX_ID', '2').to_i
    params.dig(:inbox, :id).to_i == expected
  end

  def outgoing?
    params[:message_type].to_s == 'outgoing'
  end

  def private_message?
    params[:private] == true || params[:private].to_s == 'true'
  end

  def enqueue_reply
    conversation_id = params.dig(:conversation, :id)
    content = params[:content]
    if conversation_id.blank? || content.to_s.strip.empty?
      Rails.logger.info("[FbReply] skipping payload with conversation_id=#{conversation_id.inspect} content_blank=#{content.to_s.strip.empty?}")
      return
    end

    Webhooks::FbReplyJob.perform_later(conversation_id, content.to_s)
  end
end
