# frozen_string_literal: true

# Shared, reusable DeepSeek caller. Extracted from ReplyService#invoke_anthropic
# (use_deepseek: true) so the orchestrator and background services can reuse the
# SAME endpoint / model / API key without standing up a full ReplyService.
#
# DeepSeek reasoning models return their output in `reasoning_content`; on those
# models `content` is sometimes empty. So every parse tries reasoning_content
# FIRST, then content, then fails safe (returns nil). Callers MUST handle nil.
module Ai
  class DeepseekClient
    ENDPOINT = 'https://api.deepseek.com/v1/chat/completions'
    MODEL = 'deepseek-v4-flash'
    DEFAULT_MAX_TOKENS = 1024
    TIMEOUT_SEC = 8

    def initialize(system_prompt:, messages: [], max_tokens: DEFAULT_MAX_TOKENS, temperature: 0.7)
      @system_prompt = system_prompt.to_s
      @messages = Array(messages)
      @max_tokens = max_tokens
      @temperature = temperature
    end

    # Returns model text (reasoning_content preferred, then content) or nil on any failure.
    def chat
      api_key = ENV['DEEPSEEK_API_KEY'].to_s
      return nil if api_key.blank?

      llm_messages = @messages.map do |m|
        role = ((m[:role] || m['role']).to_s == 'assistant') ? 'assistant' : 'user'
        { role: role, content: (m[:content] || m['content']).to_s }
      end

      response = HTTParty.post(
        ENDPOINT,
        headers: {
          'Authorization' => "Bearer #{api_key}",
          'Content-Type' => 'application/json'
        },
        body: {
          model: MODEL,
          max_tokens: @max_tokens,
          temperature: @temperature,
          messages: [{ role: 'system', content: @system_prompt }, *llm_messages]
        }.to_json,
        timeout: TIMEOUT_SEC
      )

      unless response.success?
        Rails.logger.error("[DeepseekClient] HTTP #{response.code}: #{response.body.to_s[0..300]}")
        return nil
      end

      message = response.parsed_response.dig('choices', 0, 'message') || {}
      # reasoning_content FIRST (reasoning models), then content, then fail safe.
      text = message['reasoning_content'].to_s.strip
      text = message['content'].to_s.strip if text.blank?
      return nil if text.blank?

      text
    rescue StandardError => e
      Rails.logger.warn("[DeepseekClient] #{e.class}: #{e.message}")
      nil
    end

    # Convenience for a single user turn.
    def self.complete(system_prompt:, user_content:, max_tokens: DEFAULT_MAX_TOKENS, temperature: 0.7)
      new(
        system_prompt: system_prompt,
        messages: [{ role: 'user', content: user_content }],
        max_tokens: max_tokens,
        temperature: temperature
      ).chat
    end
  end
end
