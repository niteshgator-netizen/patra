# frozen_string_literal: true

require 'base64'
require 'net/http'
require 'json'
require 'uri'

module Ai
  class ImagePaymentExtractor
    GEMINI_MODEL = 'gemini-2.0-flash'
    MAX_OUTPUT_TOKENS = 1024
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
        "confidence": "high|medium|low",
        "raw_text": "<concatenate EVERY readable word/handle/number you can see anywhere in the image, separated by spaces, all lowercase, no punctuation removed from $handles — purpose: full-text fallback for downstream matching>",
        "transactions": [
          {
            "amount": <number>,
            "date": "<date as written, e.g. 'May 24' or 'Today', or null>",
            "counterparty_name": "<name shown on the line item, or null>",
            "counterparty_handle": "<$cashtag/@handle shown on the line item, or null>",
            "note": "<note/memo/emoji shown on the line item, or null>",
            "direction": "sent|received"
          }
        ]
      }

      If NOT a payment screenshot:
      {"is_payment": false, "confidence": "high"}

      PLATFORM IDENTIFICATION (apply in order — pick the FIRST that matches):

      1. PayPal — strong markers: the literal word "PayPal" anywhere on the receipt; the PayPal wordmark (dark blue "Pay" + light blue "Pal"); recipient or sender shown as an email address (containing "@" and a domain like gmail.com / hotmail.com / etc); the words "Completed", "Sent", or "Payment sent" in PayPal's typography; blue color scheme (#003087 / #009cde). PayPal often shows full names like "Dev Patel" together with an email address. If you see "PayPal" written anywhere on the receipt, the platform is paypal — do not pick cashapp.

      2. Cash App — strong markers: the literal phrase "Cash App" or "Cashapp"; the white "$" inside a green square logo; bright green background or green accents (#00d632); recipient handle ALWAYS prefixed with "$" (a "cashtag") never "@"; status text "Payment Sent" or "Completed". Cash App receipts do NOT show email addresses for the recipient — only $cashtags. If the recipient field is an email address, this is NOT cashapp.

      3. Venmo — strong markers: the literal word "Venmo"; light blue background or accents (#3D95CE); recipient as @username (not $ and not email); a prominent memo / note field (often with an emoji); "Charged" or "Paid" status; transaction history feed layout.

      4. Chime — strong markers: the word "Chime"; teal / mint green branding (#1EC677); "Pay Anyone" or "Chime Pay" feature; $ChimeSign handle.

      5. Zelle — strong markers: the word "Zelle"; purple wordmark (#6D1ED4); recipient by phone number or email; bank app chrome around it (Bank of America, Chase, Wells Fargo, Citi); "Sent" status.

      DISAMBIGUATION RULES:
      - If the receipt visibly says "PayPal" but the customer's message text says "cashapp", TRUST THE SCREENSHOT. Output platform=paypal. The customer may have sent the wrong screenshot.
      - If two platforms could match, prefer the one with the strongest evidence: branded wordmark > color scheme > handle format > sender's claim.
      - If you cannot find ANY of the strong markers for any platform, output platform="unknown" and confidence="low" rather than guessing.

      OTHER RULES:
      - Return is_payment:true only if at least 70 percent confident.
      - raw_text must include $cashtags, @handles, and recipient/sender names verbatim — case-insensitive but characters preserved.
      - amount must be a number, not a string.
      - Read names, handles, and transaction_id EXACTLY as shown. Do not paraphrase. Do not invent.
      - transaction_id is critical for duplicate detection — extract it verbatim if visible.
      - transactions[] only populates when the image shows a transaction LIST (profile pages with "Your history" section, account history views, transaction feed). For a single transaction receipt, leave transactions as [] or omit it. Each item must have at minimum amount + direction. Date/counterparty_name help downstream matching.
      - For profile pages where you would normally output is_payment:false, still output is_payment:true with platform set to the detected app (cashapp/venmo/chime), amount/transaction_id/sender_name as null, AND populate transactions[] with everything visible in the history.
      - If a field is not visible or unreadable, return null. Do not guess.
    PROMPT

    def initialize(image_url)
      @image_url = image_url.to_s.strip
    end

    def extract
      return { is_payment: false, error: 'timeout' } if @image_url.blank?

      api_key = ENV['GEMINI_API_KEY'].to_s
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
          Rails.logger.error("[ImagePaymentExtractor] image download failed status=#{response.code} url=#{@image_url.to_s[0,80]}")
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

        Rails.logger.info("[ImagePaymentExtractor] downloaded #{image_bytes.bytesize} bytes status=200 media=#{media_type}")

        encoded = Base64.strict_encode64(image_bytes)
      rescue StandardError => e
        return { is_payment: false, error: 'download_error', message: e.message }
      end

      Rails.logger.info("[ImagePaymentExtractor] using model=#{GEMINI_MODEL}")

      body = {
        'contents' => [{
          'parts' => [
            { 'inlineData' => { 'mimeType' => media_type, 'data' => encoded } },
            { 'text' => VISION_PROMPT }
          ]
        }],
        'generationConfig' => { 'temperature' => 0, 'maxOutputTokens' => MAX_OUTPUT_TOKENS }
      }

      Rails.logger.info("[ImagePaymentExtractor] downloaded #{image_bytes.bytesize} bytes media_type=#{media_type}")

      response = post_json(body, api_key)

      unless response.is_a?(Net::HTTPSuccess)
        if response.code.to_s == '429'
          Rails.logger.warn("[ImagePaymentExtractor] HTTP 429 rate limit — retrying in 4s")
          sleep 4
          response = post_json(body, api_key)
          unless response.is_a?(Net::HTTPSuccess)
            Rails.logger.warn("[ImagePaymentExtractor] HTTP #{response&.code} after retry")
            return { is_payment: false, error: 'timeout' }
          end
        else
          Rails.logger.warn("[ImagePaymentExtractor] HTTP #{response&.code}")
          return { is_payment: false, error: 'timeout' }
        end
      end

      parsed = parse_json_safe(response.body)
      return { is_payment: false, error: 'parse_error' } if parsed.nil?

      raw_text = extract_text_content(parsed)
      return { is_payment: false, error: 'parse_error' } if raw_text.blank?

      json_text = strip_code_fences(raw_text)
      data = parse_json_safe(json_text)
      return { is_payment: false, error: 'parse_error' } if data.nil? || !data.is_a?(Hash)

      result = validate_and_symbolize(data)
      Rails.logger.info "[ImagePaymentExtractor] gemini_result is_payment=#{result[:is_payment]} platform=#{result[:platform]} amount=#{result[:amount]} confidence=#{result[:confidence]}"
      result
    rescue StandardError => e
      Rails.logger.warn("[ImagePaymentExtractor] #{e.class}: #{e.message}")
      { is_payment: false, error: 'timeout' }
    end

    private

    def post_json(payload_hash, api_key)
      uri = URI("https://generativelanguage.googleapis.com/v1beta/models/#{GEMINI_MODEL}:generateContent?key=#{api_key}")
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = true
      http.open_timeout = TIMEOUT_SEC
      http.read_timeout = TIMEOUT_SEC

      req = Net::HTTP::Post.new(uri)
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
      parsed.dig('candidates', 0, 'content', 'parts', 0, 'text').to_s.strip.presence
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
