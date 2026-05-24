# frozen_string_literal: true

module ClickToChat
  class LinkGenerator
    def self.generate(account:, channel:, utm_source: nil, utm_campaign: nil)
      base = case channel
             when 'facebook'
               page_id = account.inboxes.joins(:channel_api).first&.channel&.additional_attributes&.dig('fb_page_id')
               "https://m.me/#{page_id}"
             when 'instagram'
               ig_id = account.inboxes.where(channel_type: 'Channel::Instagram').first&.channel&.instagram_id
               "https://ig.me/m/#{ig_id}"
             else
               "https://patrahq.com/chat/#{account.id}"
             end

      params = { utm_source: utm_source, utm_campaign: utm_campaign }.compact
      params.any? ? "#{base}?#{params.to_query}" : base
    end
  end
end
