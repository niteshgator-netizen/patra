# frozen_string_literal: true

module Ai
  class CopilotService
    def self.suggest(conversation:, draft: '')
      return '' if conversation.blank?

      messages = conversation.messages.chat.last(10).map { |m| "#{m.message_type}: #{m.content}" }.join("\n")
      prompt = "Based on this conversation, suggest a reply for the agent. Draft so far: #{draft}\n\n#{messages}"
      call_ai(prompt)
    end

    def self.call_ai(prompt)
      return '' unless ENV['OPENAI_API_KEY'].present?

      response = HTTParty.post(
        'https://api.openai.com/v1/chat/completions',
        headers: { 'Authorization' => "Bearer #{ENV['OPENAI_API_KEY']}", 'Content-Type' => 'application/json' },
        body: { model: 'gpt-4o-mini', messages: [{ role: 'user', content: prompt }], max_tokens: 300 }.to_json
      )
      response.dig('choices', 0, 'message', 'content').to_s.strip
    rescue StandardError => e
      Rails.logger.error("[CopilotService] #{e.message}")
      ''
    end
  end
end
