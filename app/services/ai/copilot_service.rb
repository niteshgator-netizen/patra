# frozen_string_literal: true

module Ai
  class CopilotService
    def self.suggest(conversation:, draft: '')
      return '' if conversation.blank?

      messages = conversation.messages.chat.last(10).map { |m| "#{m.message_type}: #{m.content}" }.join("\n")
      prompt = "Based on this conversation, suggest a reply for the agent. Draft so far: #{draft}\n\n#{messages}"
      call_ai(prompt)
    end

    # Patra runs on DeepSeek (shared client handles retry + reasoning_content
    # fallback). The old OpenAI path silently returned '' in production because
    # OPENAI_API_KEY is not part of the Patra stack.
    def self.call_ai(prompt)
      out = Ai::DeepseekClient.complete(
        system_prompt: 'You assist a support-inbox agent. Reply with only what is asked — no preamble, no markdown.',
        user_content: prompt,
        max_tokens: 300,
        temperature: 0.4
      )
      out.to_s.strip
    rescue StandardError => e
      Rails.logger.error("[CopilotService] #{e.message}")
      ''
    end
  end
end
