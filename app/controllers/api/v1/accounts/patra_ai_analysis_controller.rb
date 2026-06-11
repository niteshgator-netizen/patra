# frozen_string_literal: true

# HB-1: on-demand AI analysis of a conversation. Reads recent messages
# (read-only), asks DeepSeek for strict JSON, persists the result ONCE to
# conversation.custom_attributes['patra_ai_analysis']. No sends.
class Api::V1::Accounts::PatraAiAnalysisController < Api::V1::Accounts::BaseController
  before_action :set_conversation

  ANALYSIS_SYSTEM_PROMPT = <<~PROMPT
    You analyze a support conversation from an online sweepstakes gaming service.
    Respond with ONLY compact JSON, no markdown, exactly this shape:
    {"intent":"<one short label, e.g. load_request/cashout/complaint/chitchat>",
     "sentiment":"positive|neutral|negative",
     "entities":["<usernames, games, amounts, payment platforms mentioned>"],
     "safety_check":{"status":"ok|review","note":"<one short line; 'review' for fraud signals, threats, chargebacks>"},
     "suggested_reply":"<max 2 short lines, human cashier voice, no bullets, never admits being AI>",
     "confidence":<integer 0-100>}
  PROMPT

  def create
    transcript = recent_transcript
    return render json: { error: 'conversation has no analyzable messages' }, status: :unprocessable_entity if transcript.blank?

    raw = begin
      Ai::DeepseekClient.complete(
        system_prompt: ANALYSIS_SYSTEM_PROMPT,
        user_content: transcript,
        max_tokens: 512,
        temperature: 0
      )
    rescue StandardError => e
      Rails.logger.error("[PatraAiAnalysis] #{e.class}: #{e.message}")
      nil
    end

    return render json: { error: 'ai unavailable — try again' }, status: :service_unavailable if raw.blank?

    analysis = parse_analysis(raw)
    return render json: { error: 'model returned unparseable output' }, status: :unprocessable_entity if analysis.nil?

    persist_analysis(analysis)
    render json: { analysis: analysis }
  end

  private

  def set_conversation
    @conversation = Current.account.conversations.find_by!(display_id: params[:conversation_id])
    authorize @conversation, :show?
  end

  def recent_transcript
    @conversation.messages
                 .where(message_type: [:incoming, :outgoing])
                 .where.not(content: [nil, ''])
                 .order(created_at: :desc)
                 .limit(30)
                 .to_a
                 .reverse
                 .map { |m| "#{m.message_type == 'incoming' ? 'player' : 'cashier'}: #{m.content.to_s[0, 300]}" }
                 .join("\n")
  end

  # Defensive parse: strip fences, grab the first {...} block, validate shape,
  # clamp confidence to 0-100. nil on anything unparseable.
  def parse_analysis(raw)
    json = raw.to_s.sub(/\A```(?:json)?\s*/i, '').sub(/\s*```\z/, '').strip
    unless json.start_with?('{')
      brace = json.match(/\{.*\}/m)
      json = brace[0] if brace
    end
    data = JSON.parse(json)
    return nil unless data.is_a?(Hash)

    safety = data['safety_check'].is_a?(Hash) ? data['safety_check'] : {}
    {
      'intent' => data['intent'].to_s,
      'sentiment' => data['sentiment'].to_s,
      'entities' => Array(data['entities']).map(&:to_s),
      'safety_check' => {
        'status' => safety['status'].to_s.presence || 'ok',
        'note' => safety['note'].to_s
      },
      'suggested_reply' => data['suggested_reply'].to_s,
      'confidence' => data['confidence'].to_i.clamp(0, 100),
      'analyzed_at' => Time.current.iso8601
    }
  rescue JSON::ParserError
    nil
  end

  def persist_analysis(analysis)
    attrs = @conversation.custom_attributes || {}
    attrs['patra_ai_analysis'] = analysis
    @conversation.update!(custom_attributes: attrs)
  end
end
