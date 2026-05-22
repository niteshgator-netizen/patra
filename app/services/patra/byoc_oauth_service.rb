# frozen_string_literal: true

module Patra
  class ByocOauthService
    class Error < StandardError; end

    def initialize(account:, code:, redirect_uri:)
      @account = account
      @code = code.to_s
      @redirect_uri = redirect_uri
      @app_id = account.meta_app_id
      @app_secret = account.meta_app_secret_encrypted
    end

    def complete!
      raise Error, 'Account has no BYOC Meta app configured' unless @account.byoc_meta_app?
      raise Error, 'Authorization code missing' if @code.blank?

      user_token = exchange_code_for_user_token!
      long_lived = exchange_for_long_lived_token!(user_token)
      user_profile = fetch_user_profile!(long_lived)
      raise Error, 'Could not fetch Facebook user profile' if user_profile.blank?

      pages = fetch_user_pages!(long_lived)
      Rails.logger.info(
        "[PatraBYOC-debug] /me/accounts returned #{pages.length} pages: " \
        "#{pages.map { |p| { id: p[:id], name: p[:name] } }.inspect}"
      )
      identity = upsert_facebook_identity!(user_profile, long_lived)
      created_channels = pages.map { |page| upsert_byoc_channel!(page, identity) }
      Rails.logger.info(
        "[PatraBYOC-debug] complete! returning #{created_channels.compact.length} " \
        "created channels of #{pages.length} pages received"
      )

      { identity: identity, pages: created_channels }
    end

    private

    def exchange_code_for_user_token!
      Facebook::PatraGraphService.exchange_oauth_code(
        code: @code,
        redirect_uri: @redirect_uri,
        app_id: @app_id,
        app_secret: @app_secret
      )
    end

    def exchange_for_long_lived_token!(short_lived_token)
      Facebook::PatraGraphService.exchange_user_token(
        short_lived_token,
        app_id: @app_id,
        app_secret: @app_secret
      )
    end

    def fetch_user_profile!(user_token)
      Facebook::PatraGraphService.fetch_user_profile(user_token)
    end

    def fetch_user_pages!(user_token)
      Facebook::PatraGraphService.fetch_managed_pages(user_token)
    end

    def upsert_facebook_identity!(profile, long_lived_user_token)
      identity = @account.facebook_identities.find_or_initialize_by(fb_user_id: profile[:fb_user_id])
      identity.fb_user_name = profile[:fb_user_name]
      identity.fb_user_avatar_url = profile[:fb_user_avatar_url]
      identity.user_access_token = long_lived_user_token
      identity.token_expires_at = 60.days.from_now
      identity.token_last_refreshed_at = Time.current
      identity.status = 'active'
      identity.save!
      identity
    end

    def upsert_byoc_channel!(page, identity)
      page_id = page[:id].to_s
      page_name = page[:name].presence || "Facebook #{page_id}"
      Rails.logger.info(
        "[PatraBYOC-debug] upserting page id=#{page_id} name=#{page[:name].inspect}"
      )

      begin
        legacy_channel = @account.facebook_pages.find_by(page_id: page_id)
        if legacy_channel&.inbox
          Rails.logger.info(
            "[PatraBYOC-debug] upserted page id=#{page_id} -> inbox=#{legacy_channel.inbox.id}"
          )
          return {
            id: page_id,
            name: legacy_channel.inbox.name,
            action: 'already_connected_legacy'
          }
        end

        user_token = identity.user_access_token
        page_token = page[:access_token].presence ||
                     Facebook::PatraGraphService.long_lived_page_access_token(page_id, user_token)
        Facebook::PatraGraphService.subscribe_page_webhook(
          page_id,
          page_token,
          app_id: @app_id,
          app_secret: @app_secret
        )

        channel_attrs = byoc_channel_attributes(page_id, page_token, user_token)
        existing = fb_bridge_channel_for_page(page_id)

        if existing
          attrs = (existing.additional_attributes || {}).stringify_keys.merge(channel_attrs)
          existing.update!(
            additional_attributes: attrs,
            facebook_identity_id: identity.id
          )
          inbox = existing.inbox
          action = 'updated'
        else
          channel = @account.api_channels.create!(
            webhook_url: '',
            hmac_mandatory: false,
            facebook_identity_id: identity.id,
            additional_attributes: channel_attrs
          )
          inbox = @account.inboxes.create!(name: page_name, channel: channel)
          add_inbox_members!(inbox)
          action = 'created'
          ::Patra::FacebookBackfillJob.perform_later(inbox.id)
        end

        Rails.logger.info("[PatraBYOC-debug] upserted page id=#{page_id} -> inbox=#{inbox.id}")

        {
          id: page_id,
          name: inbox.name,
          action: action
        }
      rescue StandardError => e
        Rails.logger.error(
          "[PatraBYOC-debug] upsert FAILED page id=#{page_id}: #{e.class} #{e.message}"
        )
        raise
      end
    end

    def byoc_channel_attributes(page_id, page_token, user_token)
      now = Time.current.iso8601
      {
        'meta_app_id' => @app_id,
        'fb_page_id' => page_id,
        'fb_page_access_token' => page_token,
        'fb_page_token_obtained_at' => now,
        'fb_user_long_lived_token' => user_token
      }
    end

    def fb_bridge_channel_for_page(page_id)
      @account.api_channels.find_by(
        ["additional_attributes->>'fb_page_id' = ?", page_id.to_s]
      )
    end

    def add_inbox_members!(inbox)
      admin_ids = @account.administrators.pluck(:id)
      return if admin_ids.blank?

      admin_ids.each do |user_id|
        inbox.add_members([user_id]) unless inbox.members.exists?(user_id)
      end
    end
  end
end
