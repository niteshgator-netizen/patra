# frozen_string_literal: true

require 'base64'
require 'net/http'
require 'json'
require 'uri'

module Ai
  class ImagePaymentExtractor
    ANTHROPIC_URL = 'https://api.anthropic.com/v1/messages'
    MODEL = 'claude-haiku-4-5-20251001'
    MAX_TOKENS = 400
    TIMEOUT_SEC = 15

    VISION_PROMPT = <<~'PROMPT'.freeze
      You are analyzing a screenshot from a customer of an online gaming/sweepstakes platform. Determine if this is a payment confirmation screenshot and extract every identifying detail.

      Respond with ONLY valid JSON, no markdown fences, no explanation.

      If IT IS a payment screenshot:
      {
        "is_payment": true,
        "platform": "cashapp|paypal|chime|venmo|varo|boltpay|zelle|applepay|usdt|unknown",
        "amount": <number in dollars, no $ sign>,
        "sender_name": "<full name of the person who sent the money as shown on the receipt, or null>",
        "sender_handle": "<$cashtag or @handle of sender if visible, or null>",
        "recipient_name": "<full name of the recipient as shown on the receipt, or null>",
        "recipient_handle": "<$cashtag or @handle of recipient if visible, or null>",
        "transaction_id": "<transaction number / reference ID / payment ID shown anywhere on the receipt, copied verbatim, or null>",
        "transaction_date": "<date as written on the receipt, e.g. 'May 11, 2026' or 'Today' or '5/11/26', or null>",
        "transaction_time": "<time as written, e.g. '5:45 PM' or '17:45', or null>",
        "status": "sent|pending|failed|completed",
        "note_or_memo": "<the 'For' / 'Note' / 'Memo' field value if shown, or null>",
        "confidence": "high|medium|low"
      }

      If NOT a payment screenshot:
      {"is_payment": false, "confidence": "high"}

      Rules:
      - Return is_payment:true only if at least 70 percent confident.
      - amount must be a number, not a string.
      - Read names, handles, and transaction_id EXACTLY as shown. Do not paraphrase. Do not invent.
      - transaction_id is critical for duplicate detection — extract it verbatim if visible.
      - If a field is not visible or unreadable, return null. Do not guess.
    PROMPT

    def initialize(image_url)
      @image_url = image_url.to_s.strip
    end

    def extract
      return { is_payment: false, error: 'timeout' } if @image_url.blank?

      api_key = ENV['ANTHROPIC_API_KEY'].to_s
      return { is_payment: false, error: 'timeout' } if api_key.blank?

      image_bytes = nil
      media_type = nil
      encoded = nil
      begin
        uri = URI.parse(@image_url)
        http = Net::HTTP.new(uri.host, uri.port)
        http.use_ssl = (uri.scheme == 'https')
        http.open_timeout = 5
        http.read_timeout = 10
        request = Net::HTTP::Get.new(uri.request_uri)
        response = http.request(request)
        unless response.is_a?(Net::HTTPSuccess)
          return { is_payment: false, error: 'download_failed', status: response.code }
        end

        image_bytes = response.body

        media_type = case @image_url.to_s.downcase
                       when /\.png(\?|$)/ then 'image/png'
                       when /\.gif(\?|$)/ then 'image/gif'
                       when /\.webp(\?|$)/ then 'image/webp'
                       else 'image/jpeg'
                       end
        if response['content-type']&.start_with?('image/')
          media_type = response['content-type'].split(';').first.strip
        end

        encoded = Base64.strict_encode64(image_bytes)
      rescue StandardError => e
        return { is_payment: false, error: 'download_error', message: e.message }
      end

      body = {
        model: MODEL,
        max_tokens: MAX_TOKENS,
        messages: [
          {
            role: 'user',
            content: [
              { type: 'image', source: { type: 'base64', media_type: media_type, data: encoded } },
              { type: 'text', text: VISION_PROMPT }
            ]
          }
        ]
      }

      Rails.logger.info("[ImagePaymentExtractor] downloaded #{image_bytes.bytesize} bytes media_type=#{media_type}")

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
