module Bella
  class TakeoverCapture
    AUTO_ADD_THRESHOLD = BellaTakeoverCandidate::AUTO_ADD_THRESHOLD
    LOW_CONFIDENCE_MARKERS = ['let me check', 'one sec', 'asking', 'idk', 'manager', '?'].freeze
    MIN_CUSTOMER_LENGTH = 5
    MIN_REPLY_LENGTH = 10

    def initialize(message)
      @message = message
      @conversation = message.conversation
    end

    def capture!
      return nil unless eligible?

      customer_msg = previous_customer_message
      return nil if customer_msg.nil?

      customer_text = customer_msg.content.to_s.strip
      human_reply = @message.content.to_s.strip
      return nil if customer_text.length < MIN_CUSTOMER_LENGTH
      return nil if human_reply.length < MIN_REPLY_LENGTH

      return nil if BellaTakeoverCandidate.exists?(
        account_id: @conversation.account_id,
        customer_text: customer_text,
        human_reply: human_reply
      )

      score = compute_confidence(customer_text, human_reply)
      status = score >= AUTO_ADD_THRESHOLD ? 'auto_added' : 'queued'

      cand = BellaTakeoverCandidate.create!(
        account_id: @conversation.account_id,
        conversation_id: @conversation.id,
        message_id: @message.id,
        customer_text: customer_text,
        human_reply: human_reply,
        confidence_score: score,
        status: status
      )

      BellaRag::IngestCandidateJob.perform_later(cand.id) if status == 'auto_added'
      cand
    rescue StandardError => e
      Rails.logger.warn("[Bella::TakeoverCapture] #{e.class}: #{e.message[0, 200]}")
      nil
    end

    private

    def eligible?
      return false unless @message.outgoing?
      return false unless @message.sender_type == 'User'
      return false if @message.private?

      labels = @conversation.cached_label_list_array
      return false if labels.include?('ai-off')

      @conversation.messages.where(sender_type: 'AgentBot').exists?
    end

    def previous_customer_message
      @conversation.messages
                   .where(message_type: :incoming)
                   .where('created_at < ?', @message.created_at)
                   .order(created_at: :desc)
                   .first
    end

    def compute_confidence(customer_text, human_reply)
      reply_lower = human_reply.downcase
      if LOW_CONFIDENCE_MARKERS.any? { |kw| reply_lower.include?(kw) }
        return 0.3
      end

      if customer_text.length.between?(20, 300) && human_reply.length.between?(20, 500)
        return 0.85
      end

      0.6
    end
  end
end
