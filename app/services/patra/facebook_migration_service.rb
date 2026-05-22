# frozen_string_literal: true

module Patra
  # Type A: Channel::FacebookPage → Channel::Api (swap channel, preserve inbox + conversations).
  # Type B: Channel::Api with fb_page_id but missing identity/token → enrich in-place.
  # Conversations belong_to :inbox (inbox_id), not channel — counts stay stable across migrate.
  class FacebookMigrationService
    class Error < StandardError; end

    def initialize(inbox:)
      @inbox = inbox
    end

    def migrate!
      case @inbox.channel_type
      when 'Channel::FacebookPage'
        swap_legacy_to_api!
      when 'Channel::Api'
        upgrade_api_to_identity_linked!
      else
        raise Error, "Inbox channel_type #{@inbox.channel_type} is not migratable"
      end
    end

    private

    def swap_legacy_to_api!
      old_channel = @inbox.channel
      page_id = old_channel.page_id.to_s
      raise Error, 'Facebook page id missing on legacy channel' if page_id.blank?

      identity = active_facebook_identity!
      user_token = identity.user_access_token
      page_token = fetch_page_token!(identity, page_id)

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
      log_conversation_count_drift(conversation_count_before, conversation_count_after)

      {
        success: true,
        inbox_id: @inbox.id,
        operation: 'swap',
        old_channel_type: 'Channel::FacebookPage',
        new_channel_type: 'Channel::Api',
        fb_page_id: page_id,
        conversation_count: conversation_count_after
      }
    end

    def upgrade_api_to_identity_linked!
      channel = @inbox.channel
      attrs = (channel.additional_attributes || {}).stringify_keys
      page_id = attrs['fb_page_id'].to_s
      raise Error, 'Channel::Api has no fb_page_id — nothing to upgrade' if page_id.blank?

      if channel.facebook_identity_id.present? && attrs['fb_page_access_token'].present?
        raise Error, 'Inbox already identity-linked and has page token. Nothing to upgrade.'
      end

      identity = active_facebook_identity!
      page_token = fetch_page_token!(identity, page_id)

      ActiveRecord::Base.transaction do
        now = Time.current.iso8601
        new_attrs = attrs.merge(
          'fb_page_id' => page_id,
          'fb_page_access_token' => page_token,
          'fb_page_token_obtained_at' => now,
          'fb_user_long_lived_token' => identity.user_access_token
        )
        channel.update!(
          additional_attributes: new_attrs,
          facebook_identity_id: identity.id
        )
      end

      Facebook::PatraGraphService.subscribe_page_webhook(page_id, page_token)

      {
        success: true,
        inbox_id: @inbox.id,
        operation: 'upgrade',
        fb_page_id: page_id,
        facebook_identity_id: identity.id
      }
    end

    def active_facebook_identity!
      identity = @inbox.account.facebook_identities.active.first
      raise Error, 'No active FacebookIdentity. Connect via Patra OAuth first.' unless identity

      identity
    end

    def fetch_page_token!(identity, page_id)
      page_token = Facebook::PatraGraphService.fetch_page_access_token(identity.user_access_token, page_id)
      raise Error, 'FB rejected page-token request. Re-authorize via Patra OAuth.' if page_token.blank?

      page_token
    end

    def log_conversation_count_drift(before_count, after_count)
      return if before_count == after_count

      Rails.logger.warn(
        "[PatraFB] migrate inbox=#{@inbox.id} conversation count changed #{before_count} -> #{after_count}"
      )
    end
  end
end
