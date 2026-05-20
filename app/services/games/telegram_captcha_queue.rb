require 'net/http'
require 'uri'
require 'json'

# Telegram-based human fallback when CAPTCHA auto-solve repeatedly fails.
# Sends the unsolved CAPTCHA image to the ops group; polls for a reply.
#
# The reply can be:
#   - 4-8 digit string (e.g. "74461") → treat as the CAPTCHA solution
#   - any other text (e.g. "skip", "abort", "try later") → treat as a
#     command. Caller decides what to do with it.
#
# Usage:
#   queue = Games::TelegramCaptchaQueue.new(slug: 'milky_way')
#   alert = queue.send_captcha_alert(image_bytes: bytes)
#   reply = queue.poll_for_reply(alert_sent_at: alert[:sent_at], timeout: 30.minutes)
#   # reply = { type: :digits, value: "74461" } or
#   #         { type: :command, value: "skip" } or
#   #         nil (timeout)
module Games
  class TelegramCaptchaQueue
    SEND_PHOTO_TIMEOUT = 30
    POLL_INTERVAL = 5      # seconds between getUpdates polls
    POLL_TIMEOUT = 25      # Telegram long-poll seconds (must be < SEND timeout)
    DIGITS_REGEX = /\A\d{4,8}\z/

    class TelegramError < StandardError; end

    def initialize(slug:, bot_token: nil, chat_id: nil)
      @slug = slug.to_s
      @bot_token = (bot_token || ENV['TELEGRAM_BOT_TOKEN']).to_s.strip
      @chat_id = (chat_id || ENV['TELEGRAM_CHAT_ID']).to_s.strip
      raise TelegramError, 'TELEGRAM_BOT_TOKEN env var not set' if @bot_token.blank?
      raise TelegramError, 'TELEGRAM_CHAT_ID env var not set' if @chat_id.blank?
    end

    # Sends the CAPTCHA image as a photo with caption. Returns:
    #   { message_id: <int>, sent_at: <unix timestamp> }
    def send_captcha_alert(image_bytes:)
      caption = "🤖 CAPTCHA needed: #{@slug}\n\n" \
                "Reply with the digits (e.g. 74461)\n" \
                "Or reply with a command: skip / abort / retry"

      boundary = "----PatraCaptchaBoundary#{SecureRandom.hex(8)}"
      body = build_multipart_body(boundary, caption, image_bytes)

      uri = URI("https://api.telegram.org/bot#{@bot_token}/sendPhoto")
      response = Net::HTTP.start(uri.host, uri.port, use_ssl: true,
                                  open_timeout: 10, read_timeout: SEND_PHOTO_TIMEOUT) do |http|
        req = Net::HTTP::Post.new(uri.request_uri)
        req['Content-Type'] = "multipart/form-data; boundary=#{boundary}"
        req.body = body
        http.request(req)
      end

      unless response.is_a?(Net::HTTPSuccess)
        raise TelegramError, "Telegram sendPhoto HTTP #{response.code}: #{response.body.to_s[0..300]}"
      end

      parsed = JSON.parse(response.body)
      unless parsed['ok']
        raise TelegramError, "Telegram sendPhoto failed: #{parsed.inspect}"
      end

      message_id = parsed.dig('result', 'message_id').to_i
      sent_at = parsed.dig('result', 'date').to_i  # unix seconds, server time
      Rails.logger.info("[TelegramCaptchaQueue] alert sent slug=#{@slug} message_id=#{message_id}")

      { message_id: message_id, sent_at: sent_at }
    end

    # Polls for a reply newer than `alert_sent_at` in the alert chat.
    # Returns: { type: :digits, value: "74461" } or { type: :command, value: "skip" } or nil.
    def poll_for_reply(alert_sent_at:, timeout: 30 * 60)
      deadline = Time.now.to_i + timeout.to_i
      offset = nil  # let Telegram return all unread updates first time

      while Time.now.to_i < deadline
        updates = get_updates(offset: offset)
        (updates || []).each do |upd|
          offset = upd['update_id'].to_i + 1  # advance regardless

          msg = upd['message']
          next if msg.nil?
          next if msg['date'].to_i < alert_sent_at  # ignore old messages

          # Only count messages in OUR chat
          chat_id = msg.dig('chat', 'id').to_s
          next unless chat_id == @chat_id

          text = msg['text'].to_s.strip
          next if text.empty?

          Rails.logger.info("[TelegramCaptchaQueue] got reply slug=#{@slug} text=#{text.inspect}")

          if text.match?(DIGITS_REGEX)
            return { type: :digits, value: text }
          else
            return { type: :command, value: text }
          end
        end

        sleep POLL_INTERVAL
      end

      Rails.logger.warn("[TelegramCaptchaQueue] timeout waiting for reply slug=#{@slug}")
      nil  # timeout
    end

    # Plain text alert (no image) — used to confirm success or final failure.
    def send_text(text)
      uri = URI("https://api.telegram.org/bot#{@bot_token}/sendMessage")
      response = Net::HTTP.post_form(uri, chat_id: @chat_id, text: text)
      unless response.is_a?(Net::HTTPSuccess)
        Rails.logger.warn("[TelegramCaptchaQueue] sendMessage HTTP #{response.code}: #{response.body.to_s[0..200]}")
      end
      response.is_a?(Net::HTTPSuccess)
    rescue StandardError => e
      Rails.logger.warn("[TelegramCaptchaQueue] sendMessage error: #{e.class}: #{e.message}")
      false
    end

    private

    def get_updates(offset:)
      params = { 'timeout' => POLL_TIMEOUT.to_s, 'allowed_updates' => '["message"]' }
      params['offset'] = offset.to_s if offset
      query = URI.encode_www_form(params)
      uri = URI("https://api.telegram.org/bot#{@bot_token}/getUpdates?#{query}")

      Net::HTTP.start(uri.host, uri.port, use_ssl: true,
                      open_timeout: 10, read_timeout: POLL_TIMEOUT + 10) do |http|
        req = Net::HTTP::Get.new(uri.request_uri)
        response = http.request(req)
        unless response.is_a?(Net::HTTPSuccess)
          Rails.logger.warn("[TelegramCaptchaQueue] getUpdates HTTP #{response.code}: #{response.body.to_s[0..200]}")
          return []
        end
        parsed = JSON.parse(response.body)
        return [] unless parsed['ok']
        parsed['result'] || []
      end
    rescue StandardError => e
      Rails.logger.warn("[TelegramCaptchaQueue] getUpdates error: #{e.class}: #{e.message}")
      []
    end

    def build_multipart_body(boundary, caption, image_bytes)
      parts = []
      parts << "--#{boundary}\r\n"
      parts << "Content-Disposition: form-data; name=\"chat_id\"\r\n\r\n"
      parts << "#{@chat_id}\r\n"
      parts << "--#{boundary}\r\n"
      parts << "Content-Disposition: form-data; name=\"caption\"\r\n\r\n"
      parts << "#{caption}\r\n"
      parts << "--#{boundary}\r\n"
      parts << "Content-Disposition: form-data; name=\"photo\"; filename=\"captcha.png\"\r\n"
      parts << "Content-Type: image/png\r\n\r\n"
      parts.join.force_encoding('ASCII-8BIT') + image_bytes.force_encoding('ASCII-8BIT') +
        "\r\n--#{boundary}--\r\n".force_encoding('ASCII-8BIT')
    end
  end
end
