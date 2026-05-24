# frozen_string_literal: true

require 'net/http'
require 'json'

module Ai
  class ConversationSummaryService
    MODEL = 'claude-haiku-4-5-20251001'
    ANTHROPIC_URL = 'https://api.anthropic.com/v1/messages'

    def initialize(messages)
      @messages = Array(messages)
    end

    def call
      text = @messages.map do |m|
        role = m.message_type_outgoing? ? 'Agent' : 'Customer'
        "#{role}: #{m.content}"
      end.join("\n")

      return 'No summary available' if text.strip.blank?

      api_key = ENV['ANTHROPIC_API_KEY'].to_s
      return 'Summary unavailable' if api_key.blank?

      body = {
        model: MODEL,
        max_tokens: 200,
        messages: [{
          role: 'user',
          content: "Summarize this conversation in 2-3 sentences. Be specific about what was discussed and any actions taken:\n\n#{text}"
        }]
      }

      response = post_json(body, api_key)
      return 'Summary unavailable' unless response.is_a?(Net::HTTPSuccess)

      parsed = JSON.parse(response.body)
      parsed.dig('content', 0, 'text') || 'No summary available'
    rescue StandardError => e
      Rails.logger.error("[ConversationSummary] failed: #{e.message}")
      'Summary unavailable'
    end

    private

    def post_json(payload, api_key)
      uri = URI(ANTHROPIC_URL)
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = true
      http.open_timeout = 8
      http.read_timeout = 8

      req = Net::HTTP::Post.new(uri)
      req['x-api-key'] = api_key
      req['anthropic-version'] = '2023-06-01'
      req['content-type'] = 'application/json'
      req.body = payload.to_json

      http.request(req)
    end
  end
end
