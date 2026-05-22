# frozen_string_literal: true

module Patra
  # Swaps Channel::FacebookPage → Channel::Api on an existing inbox.
  # Conversations belong_to :inbox (inbox_id), not channel — counts stay stable across migrate.
  class FacebookMigrationService
    class Error < StandardError; end

    def initialize(inbox:)
      @inbox = inbox
    end

    def migrate!
      raise Error, 'Inbox is not Channel::FacebookPage' unless @inbox.channel_type == 'Channel::FacebookPage'

      old_channel = @inbox.channel
      page_id = old_channel.page_id.to_s
      raise Error, 'Facebook page id missing on legacy channel' if page_id.blank?

      identity = @inbox.account.facebook_identities.active.first
      raise Error, 'No active FacebookIdentity for this account. Connect Facebook via Patra OAuth first.' unless identity

      user_token = identity.user_access_token
      page_token = Facebook::PatraGraphService.fetch_page_access_token(user_token, page_id)
      raise Error, 'FB rejected page-token request. Re-authorize via Patra OAuth.' if page_token.blank?

      conversation_count_before = @inbox.conversations.count
      old_channel_id = old_channel.id

      ActiveRecord::Base.transaction do
        now = Time.current.iso8601
        new_channel = @inbox.account.api_channels.create!(
          webhook_url: '',
          hmac_mandatory: false,
          facebook_identity_id: identity.id,
          additional_attributes: {
            'fb_page_id' => page_id,
            'fb_page_access_token' => page_token,
            'fb_page_token_obtained_at' => now,
            'fb_user_long_lived_token' => user_token
          }
        )

        @inbox.update!(
          channel_type: 'Channel::Api',
          channel_id: new_channel.id
        )

        # Repoint inbox first — Channelable#dependent :destroy_async on channel would delete inbox if still linked.
        Channel::FacebookPage.where(id: old_channel_id).destroy_all
      end

      Facebook::PatraGraphService.subscribe_page_webhook(page_id, page_token)

      conversation_count_after = @inbox.conversations.reload.count
      if conversation_count_before != conversation_count_after
        Rails.logger.warn(
          "[PatraFB] migrate inbox=#{@inbox.id} conversation count changed #{conversation_count_before} -> #{conversation_count_after}"
        )
      end

      {
        success: true,
        inbox_id: @inbox.id,
        old_channel_type: 'Channel::FacebookPage',
        new_channel_type: 'Channel::Api',
        fb_page_id: page_id,
        conversation_count: conversation_count_after
      }
    end
  end
end
