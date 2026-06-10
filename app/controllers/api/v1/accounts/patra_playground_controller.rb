# frozen_string_literal: true

# HB-2: admin playground — test Bella's persona against a message without
# touching a real conversation. No persistence, no sends, no side effects.
class Api::V1::Accounts::PatraPlaygroundController < Api::V1::Accounts::BaseController
  def create
    message = params[:message].to_s.strip
    return render json: { error: 'message required' }, status: :unprocessable_entity if message.blank?

    prompt = Ai::PlaygroundPromptBuilder.build(account: Current.account, context: params[:context])

    reply = begin
      Ai::DeepseekClient.complete(
        system_prompt: prompt,
        user_content: message,
        max_tokens: 200,
        temperature: 0.7
      )
    rescue StandardError => e
      Rails.logger.error("[PatraPlayground] #{e.class}: #{e.message}")
      nil
    end

    return render json: { error: 'ai unavailable — try again' }, status: :service_unavailable if reply.blank?

    # Defensive enforcement of the 2-line persona cap.
    reply = reply.to_s.strip.split("\n").reject(&:blank?).first(2).join("\n")

    render json: { reply: reply, prompt: prompt }
  end
end
