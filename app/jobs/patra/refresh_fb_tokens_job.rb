# frozen_string_literal: true

# Weekly maintenance: refresh Facebook page access tokens stored on API-channel
# inboxes before Meta invalidates stale credentials (best-effort).
class Patra::RefreshFbTokensJob < ApplicationJob
  queue_as :low

  TOKEN_REFRESH_AGE = 50.days

  def perform
    fb_api_inboxes.find_each do |inbox|
      refresh_inbox_tokens(inbox)
    rescue StandardError => e
      Rails.logger.error("[PatraFB] token refresh inbox=#{inbox.id} #{e.class}: #{e.message}")
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

  def refresh_inbox_tokens(inbox)
    channel = inbox.channel
    attrs = channel.additional_attributes || {}
    page_id = attrs['fb_page_id'].to_s
    user_token = attrs['fb_user_long_lived_token'].to_s
    obtained = parse_obtained_at(attrs['fb_page_token_obtained_at'])
    return if page_id.blank? || user_token.blank?
    return if obtained.present? && obtained > TOKEN_REFRESH_AGE.ago

    new_page_token = Facebook::PatraGraphService.refresh_page_access_token(page_id, user_token)
    return if new_page_token.blank?

    attrs = attrs.merge(
      'fb_page_access_token' => new_page_token,
      'fb_page_token_obtained_at' => Time.current.iso8601
    )
    channel.update!(additional_attributes: attrs)
    Rails.logger.info("[PatraFB] refreshed page token inbox=#{inbox.id} page=#{page_id}")
  end

  def parse_obtained_at(raw)
    return nil if raw.blank?

    Time.zone.parse(raw.to_s)
  rescue ArgumentError
    nil
  end
end
