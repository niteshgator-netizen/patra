# frozen_string_literal: true

module Ai
  class ConversationSummaryService
    XAI_URL = 'https://api.x.ai/v1/chat/completions'.freeze
    MODEL = ENV.fetch('XAI_MODEL', 'grok-4.3').freeze

    def initialize(messages)
      @messages = Array(messages)
    end

    def call
      text = @messages.map do |m|
        role = m.outgoing? ? 'Agent' : 'Customer'
        "#{role}: #{m.content}"
      end.join("\n")

      return 'No summary available' if text.strip.blank?

      api_key = ENV['DEEPSEEK_API_KEY'].to_s
      return 'Summary unavailable' if api_key.blank?

      response = HTTParty.post(
        'https://api.deepseek.com/v1/chat/completions',
        headers: {
          'Authorization' => "Bearer #{api_key}",
          'Content-Type' => 'application/json'
        },
        body: {
          model: ENV.fetch('DEEPSEEK_MODEL', 'deepseek-v4-flash'),
          max_tokens: 600,
          messages: [{
            role: 'user',
            content: "Summarize this conversation in 2-3 sentences. Be specific about what was discussed and any actions taken:\n\n#{text}"
          }]
        }.to_json,
        timeout: 30
      )

      return 'Summary unavailable' unless response.success?

      msg = response.parsed_response.dig('choices', 0, 'message') || {}
      (msg['reasoning_content'].to_s.strip.presence || msg['content'].to_s.strip.presence) || 'No summary available'
    rescue StandardError => e
      Rails.logger.error("[ConversationSummaryService] failed: #{e.message}")
      'Summary unavailable'
    end
  end
end
