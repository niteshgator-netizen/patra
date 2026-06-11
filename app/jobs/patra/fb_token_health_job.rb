# frozen_string_literal: true

# MEGA2 P11 - daily FB page-token health check. Validates each bridge inbox's
# page token with the cheapest possible Graph call (GET /{page_id}?fields=id
# using the page token itself) and Telegrams a 5-part alert naming the
# inbox/page when a token is dead, missing, or inside the expiry-warning
# window. Read-only: never refreshes or mutates tokens (that stays with the
# weekly Patra::RefreshFbTokensJob). Failures rescued per token.
class Patra::FbTokenHealthJob < ApplicationJob
  queue_as :low

  GRAPH_BASE = 'https://graph.facebook.com/v18.0'
  HTTP_TIMEOUT = 15
  # Meta long-lived page tokens live ~60 days (same heuristic as RefreshFbTokensJob).
  TOKEN_EXPIRY_WARNING_AGE = 53.days

  def perform
    fb_api_inboxes.find_each do |inbox|
      check_inbox(inbox)
    rescue StandardError => e
      Rails.logger.error("[FbTokenHealth] inbox=#{inbox.id} #{e.class}: #{e.message}")
    end
  end

  private

  def fb_api_inboxes
    Inbox.where(channel_type: 'Channel::Api')
         .joins(
           'INNER JOIN channel_api ON channel_api.id = inboxes.channel_id ' \
           "AND inboxes.channel_type = 'Channel::Api'"
         )
         .where("channel_api.additional_attributes->>'fb_page_id' IS NOT NULL")
  end

  def check_inbox(inbox)
    attrs = inbox.channel.additional_attributes || {}
    page_id = attrs['fb_page_id'].to_s
    token = attrs['fb_page_access_token'].to_s
    return if page_id.blank?

    if token.blank?
      alert(inbox, page_id, 'no fb_page_access_token stored at all', 'reconnect the page')
      return
    end

    status = validate_token(page_id, token)
    case status
    when :invalid
      alert(inbox, page_id, 'page token is DEAD (Graph rejected it, OAuth 190/401)', 'reconnect the page or re-run the token refresh')
      return
    when :unreachable
      Rails.logger.warn("[FbTokenHealth] inbox=#{inbox.id} page=#{page_id} Graph unreachable - skipping verdict (no alert)")
      return
    end

    obtained = parse_obtained_at(attrs['fb_page_token_obtained_at'])
    return unless obtained.present? && obtained <= TOKEN_EXPIRY_WARNING_AGE.ago

    alert(inbox, page_id,
          "token still works but was obtained #{obtained.to_date} (older than #{TOKEN_EXPIRY_WARNING_AGE.inspect}) - expiry imminent",
          'refresh now (weekly refresh job) or reconnect before it dies')
  end

  # :ok / :invalid / :unreachable. The /{page_id}?fields=id call is the
  # cheapest authenticated request - no message quota, no page data.
  def validate_token(page_id, token)
    response = HTTParty.get(
      "#{GRAPH_BASE}/#{page_id}",
      query: { fields: 'id', access_token: token },
      timeout: HTTP_TIMEOUT
    )
    return :ok if response.success?

    body = response.parsed_response
    code = body.is_a?(Hash) ? body.dig('error', 'code').to_i : 0
    return :invalid if code == 190 || response.code.to_i == 401

    # Rate limits / 5xx / odd errors: token state unknown - do not cry wolf.
    Rails.logger.warn("[FbTokenHealth] page=#{page_id} Graph HTTP #{response.code} fb_code=#{code}")
    :unreachable
  rescue StandardError => e
    Rails.logger.warn("[FbTokenHealth] page=#{page_id} validate raised #{e.class}: #{e.message}")
    :unreachable
  end

  def alert(inbox, page_id, what, fix)
    text = "PLAYER WANTS: their FB messages answered (inbox '#{inbox.name}' / page #{page_id}) | " \
           "ALREADY DONE: daily token check - #{what} | " \
           'STILL LEFT: messages on this page will silently stop flowing when the token dies | ' \
           "BELLA SUGGESTS: #{fix} | " \
           "NEEDS FROM HUMAN: restore a valid page token for inbox ##{inbox.id}"
    Games::TelegramNotifier.send_to_cashout_group(text)
  rescue StandardError => e
    Rails.logger.error("[FbTokenHealth] telegram failed inbox=#{inbox.id}: #{e.class}: #{e.message}")
  end

  def parse_obtained_at(raw)
    return nil if raw.blank?

    Time.zone.parse(raw.to_s)
  rescue ArgumentError
    nil
  end
end
