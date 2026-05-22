# frozen_string_literal: true

class Api::V1::Accounts::Patra::FacebookConnectController < Api::V1::Accounts::BaseController
  before_action :check_admin_authorization?
  before_action :validate_fb_connect_pages_limit!, only: [:fb_connect_pages]

  def fb_connect
    short_token = params.require(:access_token).to_s
    long_lived = Facebook::PatraGraphService.exchange_user_token(short_token)
    pages = Facebook::PatraGraphService.fetch_managed_pages(long_lived)

    profile = Facebook::PatraGraphService.fetch_user_profile(long_lived)
    identity = upsert_facebook_identity!(profile, long_lived) if profile&.dig(:fb_user_id).present?
    unless identity
      Rails.logger.warn('[PatraFB] fb_connect could not fetch FB user profile, proceeding without FacebookIdentity')
    end

    render json: {
      pages: pages,
      user_access_token: long_lived,
      facebook_identity_id: identity&.id,
      fb_user_name: profile&.dig(:fb_user_name)
    }
  rescue ArgumentError, StandardError => e
    Rails.logger.error("[PatraFB] fb_connect failed: #{e.class}: #{e.message}")
    render json: { error: e.message }, status: :unprocessable_entity
  end

  def fb_connect_pages
    user_token = params.require(:user_access_token).to_s
    pages_param = params.require(:pages)
    raise ActionController::ParameterMissing, 'pages' unless pages_param.is_a?(Array)

    identity_id = resolved_facebook_identity_id
    created = []
    ActiveRecord::Base.transaction do
      pages_param.each do |raw|
        page = raw.permit(:id, :name, :access_token).to_h
        next if page['id'].blank? || page['access_token'].blank?

        created << create_fb_api_inbox!(page, user_token, facebook_identity_id: identity_id)
      end
    end

    render json: { inboxes: created, facebook_identity_id: identity_id }
  rescue ActionController::ParameterMissing => e
    render json: { error: e.message }, status: :bad_request
  rescue ActiveRecord::RecordInvalid => e
    Rails.logger.error("[PatraFB] fb_connect_pages validation: #{e.message}")
    render json: { error: e.message }, status: :unprocessable_entity
  rescue StandardError => e
    Rails.logger.error("[PatraFB] fb_connect_pages failed: #{e.class}: #{e.message}")
    render json: { error: e.message }, status: :unprocessable_entity
  end

  private

  def upsert_facebook_identity!(profile, long_lived_user_token)
    identity = Current.account.facebook_identities.find_or_initialize_by(fb_user_id: profile[:fb_user_id])
    identity.fb_user_name = profile[:fb_user_name]
    identity.fb_user_avatar_url = profile[:fb_user_avatar_url]
    identity.user_access_token = long_lived_user_token
    identity.token_expires_at = 60.days.from_now
    identity.token_last_refreshed_at = Time.current
    identity.status = 'active'
    identity.save!
    identity
  end

  def resolved_facebook_identity_id
    id = params[:facebook_identity_id].presence
    return nil unless id

    Current.account.facebook_identities.find_by(id: id)&.id
  end

  def validate_fb_connect_pages_limit!
    pages_param = params[:pages]
    n = pages_param.is_a?(Array) ? pages_param.size : 0
    return if n.zero?

    limit = Current.account.usage_limits[:inboxes]
    return if Current.account.inboxes.count + n <= limit

    render_payment_required('Account limit exceeded. Upgrade to a higher plan')
  end

  def create_fb_api_inbox!(page, user_long_lived_token, facebook_identity_id: nil)
    page_id = page['id'].to_s
    page_name = page['name'].presence || "Facebook #{page_id}"

    long_page_token = Facebook::PatraGraphService.long_lived_page_access_token(page_id, user_long_lived_token)
    Facebook::PatraGraphService.subscribe_page_webhook(page_id, long_page_token)

    channel_attrs = fb_channel_attributes(page_id, long_page_token, user_long_lived_token)
    channel = Current.account.api_channels.create!(
      webhook_url: '',
      hmac_mandatory: false,
      facebook_identity_id: facebook_identity_id,
      additional_attributes: channel_attrs
    )

    inbox = Current.account.inboxes.create!(name: page_name, channel: channel)
    inbox.add_members([current_user.id]) unless inbox.members.exists?(current_user.id)

    { id: inbox.id, name: inbox.name, channel_id: channel.id, facebook_identity_id: facebook_identity_id }
  end

  def fb_channel_attributes(page_id, page_token, user_token)
    now = Time.current.iso8601
    {
      'fb_page_id' => page_id,
      'fb_page_access_token' => page_token,
      'fb_page_token_obtained_at' => now,
      'fb_user_long_lived_token' => user_token
    }
  end
end
