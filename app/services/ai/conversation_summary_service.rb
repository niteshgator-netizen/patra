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
        role = m.message_type_outgoing? ? 'Agent' : 'Customer'
        "#{role}: #{m.content}"
      end.join("\n")

      return 'No summary available' if text.strip.blank?

      api_key = ENV['XAI_API_KEY'].to_s
      return 'Summary unavailable' if api_key.blank?

      response = HTTParty.post(
        XAI_URL,
        headers: {
          'Authorization' => "Bearer #{api_key}",
          'Content-Type' => 'application/json'
        },
        body: {
          model: MODEL,
          max_tokens: 200,
          messages: [{
            role: 'user',
            content: "Summarize this conversation in 2-3 sentences. Be specific about what was discussed and any actions taken:\n\n#{text}"
          }]
        }.to_json,
        timeout: 8
      )

      return 'Summary unavailable' unless response.success?

      response.parsed_response.dig('choices', 0, 'message', 'content') || 'No summary available'
    rescue StandardError => e
      Rails.logger.error("[ConversationSummary] failed: #{e.message}")
      'Summary unavailable'
    end
  end
end
