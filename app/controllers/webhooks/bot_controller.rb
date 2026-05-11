# Custom /bot endpoint that replaces the facebook-messenger gem's mounted Rack
# server. The built-in Chatwoot Facebook channel pipeline is broken on this
# deployment, so we ack Facebook's webhook fast and hand off to a background
# job that posts events into Chatwoot via the public REST API.
#
#   GET  /bot — verification handshake (FB_VERIFY_TOKEN, ENV-only)
#   POST /bot — page event delivery; entries are flattened into one job per
#               message event.
#
# We deliberately:
#   - return 200 even on internal failure so Facebook never disables the
#     webhook subscription (any failure that escapes is logged loudly);
#   - skip echoes (`message.is_echo == true`), delivery/read receipts, and
#     non-text messages — only honest user-typed messages flow through.
class Webhooks::BotController < ActionController::API
  # GET /bot
  def verify
    expected = ENV.fetch('FB_VERIFY_TOKEN', '').to_s
    if expected.present? && params['hub.verify_token'].to_s == expected
      Rails.logger.info('[BotBridge] verify handshake succeeded')
      render plain: params['hub.challenge'].to_s
    else
      Rails.logger.warn('[BotBridge] verify handshake failed — invalid token')
      head :unauthorized
    end
  end

  # POST /bot
  def events
    payload = params.to_unsafe_hash
    Rails.logger.info("[BotBridge] received webhook object=#{payload[:object]} entries=#{Array(payload[:entry]).size}")

    if payload[:object].to_s != 'page'
      Rails.logger.warn("[BotBridge] ignoring non-page object=#{payload[:object]}")
      return head :ok
    end

    enqueue_message_events(payload)
    head :ok
  rescue StandardError => e
    # Never let an internal blow-up propagate to Facebook — they will mark the
    # subscription unhealthy and back off retries. Log and ack.
    Rails.logger.error("[BotBridge] events handler crashed: #{e.class}: #{e.message}\n#{e.backtrace&.first(5)&.join("\n")}")
    head :ok
  end

  private

  def enqueue_message_events(payload)
    Array(payload[:entry]).each do |entry|
      page_id = entry[:id].to_s
      Array(entry[:messaging]).each do |messaging|
        next unless processable?(messaging)

        job_payload = messaging.deep_stringify_keys.merge('_patra_fb_page_id' => page_id)
        Webhooks::FacebookBridgeJob.perform_later(job_payload)
      rescue StandardError => e
        Rails.logger.error("[BotBridge] failed to enqueue messaging event: #{e.class}: #{e.message}")
      end
    end
  end

  def processable?(messaging)
    return false unless messaging.is_a?(Hash)

    message = messaging[:message]
    return false if message.blank? # delivery / read receipts / postbacks
    return false if message[:is_echo] # outgoing echoes from the page itself
    return false if message[:text].to_s.strip.empty? # attachments-only / stickers

    true
  end
end
