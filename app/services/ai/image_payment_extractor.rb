# frozen_string_literal: true

require 'net/http'
require 'json'
require 'uri'

module Ai
  class ImagePaymentExtractor
    ANTHROPIC_URL = 'https://api.anthropic.com/v1/messages'
    MODEL = 'claude-haiku-4-5-20251001'
    MAX_TOKENS = 200
    TIMEOUT_SEC = 15

    VISION_PROMPT = <<~PROMPT.freeze
      You are analyzing a screenshot from a customer of an online gaming/sweepstakes platform. Determine if this is a payment confirmation screenshot.

      Respond with ONLY valid JSON, no markdown fences, no explanation.

      If IT IS a payment screenshot:
      {"is_payment": true, "platform": "cashapp|paypal|chime|venmo|varo|boltpay|zelle|applepay|unknown", "amount": <number in dollars, no $ sign>, "recipient": "<handle or null>", "status": "sent|pending|failed|completed", "confidence": "high|medium|low"}

      If NOT a payment screenshot (game screenshot, selfie, meme, ID, document, anything else):
      {"is_payment": false, "confidence": "high"}

      Rules:
      - Only return is_payment:true if at least 70% confident
      - amount must be a number, not a string
      - If you cannot read the amount clearly, return is_payment:false
    PROMPT

    def initialize(image_url)
      @image_url = image_url.to_s.strip
    end

    def extract
      return { is_payment: false, error: 'timeout' } if @image_url.blank?

      api_key = ENV['ANTHROPIC_API_KEY'].to_s
      return { is_payment: false, error: 'timeout' } if api_key.blank?

      body = {
        model: MODEL,
        max_tokens: MAX_TOKENS,
        messages: [
          {
            role: 'user',
            content: [
              { type: 'image', source: { type: 'url', url: @image_url } },
              { type: 'text', text: VISION_PROMPT }
            ]
          }
        ]
      }

      response = post_json(body, api_key)

      unless response.is_a?(Net::HTTPSuccess)
        Rails.logger.warn("[ImagePaymentExtractor] HTTP #{response&.code}")
        return { is_payment: false, error: 'timeout' }
      end

      parsed = parse_json_safe(response.body)
      return { is_payment: false, error: 'parse_error' } if parsed.nil?

      raw_text = extract_text_content(parsed)
      return { is_payment: false, error: 'parse_error' } if raw_text.blank?

      json_text = strip_code_fences(raw_text)
      data = parse_json_safe(json_text)
      return { is_payment: false, error: 'parse_error' } if data.nil? || !data.is_a?(Hash)

      validate_and_symbolize(data)
    rescue StandardError => e
      Rails.logger.warn("[ImagePaymentExtractor] #{e.class}: #{e.message}")
      { is_payment: false, error: 'timeout' }
    end

    private

    def post_json(payload_hash, api_key)
      uri = URI(ANTHROPIC_URL)
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = true
      http.open_timeout = TIMEOUT_SEC
      http.read_timeout = TIMEOUT_SEC

      req = Net::HTTP::Post.new(uri)
      req['x-api-key'] = api_key
      req['anthropic-version'] = '2023-06-01'
      req['content-type'] = 'application/json'
      req.body = payload_hash.to_json

      http.request(req)
    end

    def parse_json_safe(raw)
      JSON.parse(raw.to_s)
    rescue JSON::ParserError
      nil
    end

    def extract_text_content(parsed)
      blocks = parsed['content']
      return nil unless blocks.is_a?(Array)

      texts = blocks.filter_map do |block|
        next unless block.is_a?(Hash) && block['type'] == 'text'

        block['text'].to_s
      end
      texts.join.strip.presence
    end

    def strip_code_fences(text)
      s = text.to_s.strip
      s = s.sub(/\A```(?:json)?\s*/i, '')
      s = s.sub(/\s*```\z/, '')
      s.strip
    end

    def validate_and_symbolize(data)
      sym = data.deep_symbolize_keys
      unless sym.key?(:is_payment) && sym.key?(:confidence)
        return { is_payment: false, error: 'parse_error' }
      end

      sym
    end
  end
end
