# frozen_string_literal: true

# Shared, reusable DeepSeek caller. Extracted from ReplyService#invoke_anthropic
# (use_deepseek: true) so the orchestrator and background services can reuse the
# SAME endpoint / model / API key without standing up a full ReplyService.
#
# Parse order (R-I invariant — June 11 audit): `content` FIRST, then
# `reasoning_content` ONLY as a fallback when content is empty. deepseek-v4-flash
# puts the answer in content and the chain-of-thought in reasoning_content;
# preferring reasoning leaks CoT to customers. Fails safe (returns nil) —
# callers MUST handle nil.
module Ai
  class DeepseekClient
    ENDPOINT = 'https://api.deepseek.com/v1/chat/completions'
    MODEL = 'deepseek-v4-flash'
    DEFAULT_MAX_TOKENS = 1024
    TIMEOUT_SEC = 8
    # One retry on transient failures (5xx / timeouts). 4xx never retries —
    # a bad request stays bad, and retrying auth errors just burns the budget.
    MAX_ATTEMPTS = 2

    def initialize(system_prompt:, messages: [], max_tokens: DEFAULT_MAX_TOKENS, temperature: 0.7)
      @system_prompt = system_prompt.to_s
      @messages = Array(messages)
      @max_tokens = max_tokens
      @temperature = temperature
    end

    # Returns model text (content first, reasoning_content fallback) or nil on any failure.
    def chat
      api_key = ENV['DEEPSEEK_API_KEY'].to_s
      return nil if api_key.blank?

      llm_messages = @messages.map do |m|
        role = ((m[:role] || m['role']).to_s == 'assistant') ? 'assistant' : 'user'
        { role: role, content: (m[:content] || m['content']).to_s }
      end

      response = post_with_retry(
        headers: {
          'Authorization' => "Bearer #{api_key}",
          'Content-Type' => 'application/json'
        },
        body: {
          model: MODEL,
          max_tokens: @max_tokens,
          temperature: @temperature,
          messages: [{ role: 'system', content: @system_prompt }, *llm_messages]
        }.to_json
      )
      return nil if response.nil?

      unless response.success?
        Rails.logger.error("[DeepseekClient] HTTP #{response.code}: #{response.body.to_s[0..300]}")
        return nil
      end

      message = response.parsed_response.dig('choices', 0, 'message') || {}
      # content FIRST (the real answer); reasoning_content only as a fallback when
      # content is empty. deepseek-v4-flash returns the answer in content + the
      # chain-of-thought in reasoning_content; preferring reasoning leaked CoT.
      text = message['content'].to_s.strip
      text = message['reasoning_content'].to_s.strip if text.blank?
      return nil if text.blank?

      text
    rescue StandardError => e
      Rails.logger.warn("[DeepseekClient] #{e.class}: #{e.message}")
      nil
    end

    private

    # POST with one retry on 5xx or network timeout. Returns the last response
    # (callers nil-check via success?), or raises on a final network error —
    # chat's blanket rescue converts that to nil.
    def post_with_retry(headers:, body:)
      response = nil
      MAX_ATTEMPTS.times do |i|
        begin
          response = HTTParty.post(ENDPOINT, headers: headers, body: body, timeout: TIMEOUT_SEC)
        rescue Net::OpenTimeout, Net::ReadTimeout, Errno::ECONNRESET, Errno::ECONNREFUSED => e
          raise if i + 1 >= MAX_ATTEMPTS

          Rails.logger.warn("[DeepseekClient] #{e.class} — retrying (#{i + 1}/#{MAX_ATTEMPTS - 1})")
          next
        end
        break unless response.code.to_i >= 500 && i + 1 < MAX_ATTEMPTS

        Rails.logger.warn("[DeepseekClient] HTTP #{response.code} — retrying (#{i + 1}/#{MAX_ATTEMPTS - 1})")
      end
      response
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
