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
      fb_user_name: profile&.dig(:fb_user_name),
      already_connected_fb_page_ids: already_connected_fb_page_ids,
      already_connected_pages: already_connected_pages_payload
    }
  rescue ArgumentError, StandardError => e
    Rails.logger.error("[PatraFB] fb_connect failed: #{e.class}: #{e.message}")
    render json: { error: e.message }, status: :unprocessable_entity
  end

  # Response contract:
  #   { pages: [{ fb_page_id, inbox_id, name, action: 'created'|'updated'|'already_connected_legacy' }],
  #     facebook_identity_id: Integer }
  # Idempotent: legacy Channel::FacebookPage → skip; Channel::Api with fb_page_id → update; else create.
  def fb_connect_pages
    user_token = params.require(:user_access_token).to_s
    pages_param = params.require(:pages)
    raise ActionController::ParameterMissing, 'pages' unless pages_param.is_a?(Array)

    identity_id = resolved_facebook_identity_id
    results = []
    ActiveRecord::Base.transaction do
      pages_param.each do |raw|
        page = raw.permit(:id, :name, :access_token).to_h
        next if page['id'].blank? || page['access_token'].blank?

        results << connect_page!(page, user_token, facebook_identity_id: identity_id)
      end
    end

    render json: { pages: results, facebook_identity_id: identity_id }
  rescue ActionController::ParameterMissing => e
    render json: { error: e.message }, status: :bad_request
  rescue ActiveRecord::RecordInvalid => e
    Rails.logger.error("[PatraFB] fb_connect_pages validation: #{e.message}")
    render json: { error: e.message }, status: :unprocessable_entity
  rescue StandardError => e
    Rails.logger.error("[PatraFB] fb_connect_pages failed: #{e.class}: #{e.message}")
    render json: { error: e.message }, status: :unprocessable_entity
  end

  def migrate_fb_to_api
    inbox = Current.account.inboxes.find(params[:inbox_id])
    result = ::Patra::FacebookMigrationService.new(inbox: inbox).migrate!
    render json: result
  rescue ::Patra::FacebookMigrationService::Error => e
    render json: { error: e.message }, status: :unprocessable_entity
  end

  def get_meta_app
    account = Current.account
    render json: {
      has_byoc_app: account.byoc_meta_app?,
      app_id: account.meta_app_id,
      app_validated_at: account.meta_app_validated_at
    }
  end

  def save_meta_app
    result = ::Patra::MetaAppValidator.new(
      app_id: params.require(:app_id),
      app_secret: params.require(:app_secret)
    ).validate!

    Current.account.update!(
      meta_app_id: result[:app_id],
      meta_app_secret_encrypted: params[:app_secret],
      meta_app_validated_at: Time.current
    )

    render json: { success: true, app_id: result[:app_id], app_name: result[:app_name] }
  rescue ::Patra::MetaAppValidator::Error => e
    render json: { error: e.message }, status: :unprocessable_entity
  end

  def delete_meta_app
    Current.account.update!(meta_app_id: nil, meta_app_secret_encrypted: nil, meta_app_validated_at: nil)
    render json: { success: true }
  end

  def byoc_oauth_url
    account = Current.account
    unless account.byoc_meta_app?
      return render(json: { error: 'No Meta app configured. Save credentials first.' }, status: :unprocessable_entity)
    end

    state = ::Patra::OauthState.generate(account_id: account.id)
    scope = 'pages_show_list,pages_manage_metadata,pages_messaging,pages_read_engagement'
    redirect_uri = patra_oauth_redirect_uri
    url = "https://www.facebook.com/#{facebook_dialog_version}/dialog/oauth?" + {
      client_id: account.meta_app_id,
      redirect_uri: redirect_uri,
      state: state,
      scope: scope,
      response_type: 'code'
    }.to_query

    render json: { url: url, redirect_uri: redirect_uri }
  end

  private

  def patra_oauth_redirect_uri
    "#{ENV.fetch('FRONTEND_URL', 'https://patrahq.com').to_s.chomp('/')}/patra/oauth/callback"
  end

  def facebook_dialog_version
    (GlobalConfigService.load('FACEBOOK_API_VERSION', 'v18.0').presence || 'v18.0').to_s.delete_prefix('v')
  end

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

  def already_connected_pages_payload
    entries = []
    Current.account.api_channels
             .where("additional_attributes->>'fb_page_id' IS NOT NULL")
             .find_each do |channel|
      page_id = channel.additional_attributes['fb_page_id'].to_s
      next if page_id.blank?

      entries << { fb_page_id: page_id, legacy: false }
    end
    Current.account.facebook_pages.find_each do |channel|
      page_id = channel.page_id.to_s
      next if page_id.blank?

      entries << { fb_page_id: page_id, legacy: true }
    end
    entries.uniq { |e| e[:fb_page_id] }
  end

  def already_connected_fb_page_ids
    already_connected_pages_payload.map { |e| e[:fb_page_id] }
  end

  def legacy_fb_channel_for_page(page_id)
    Current.account.facebook_pages.find_by(page_id: page_id.to_s)
  end

  def fb_bridge_channel_for_page(page_id)
    Current.account.api_channels.find_by(
      ["additional_attributes->>'fb_page_id' = ?", page_id.to_s]
    )
  end

  def validate_fb_connect_pages_limit!
    pages_param = params[:pages]
    return unless pages_param.is_a?(Array)

    new_count = pages_param.count do |raw|
      page_id = (raw[:id] || raw['id']).to_s
      next false if page_id.blank?

      legacy_fb_channel_for_page(page_id).blank? && fb_bridge_channel_for_page(page_id).blank?
    end
    return if new_count.zero?

    limit = Current.account.usage_limits[:inboxes]
    return if Current.account.inboxes.count + new_count <= limit

    render_payment_required('Account limit exceeded. Upgrade to a higher plan')
  end

  def connect_page!(page, user_long_lived_token, facebook_identity_id: nil)
    page_id = page['id'].to_s
    legacy_channel = legacy_fb_channel_for_page(page_id)
    if legacy_channel&.inbox
      return {
        fb_page_id: page_id,
        inbox_id: legacy_channel.inbox.id,
        name: legacy_channel.inbox.name,
        action: 'already_connected_legacy'
      }
    end

    upsert_fb_api_inbox!(page, user_long_lived_token, facebook_identity_id: facebook_identity_id)
  end

  def upsert_fb_api_inbox!(page, user_long_lived_token, facebook_identity_id: nil)
    page_id = page['id'].to_s
    page_name = page['name'].presence || "Facebook #{page_id}"

    long_page_token = Facebook::PatraGraphService.long_lived_page_access_token(page_id, user_long_lived_token)
    Facebook::PatraGraphService.subscribe_page_webhook(page_id, long_page_token)

    channel_attrs = fb_channel_attributes(page_id, long_page_token, user_long_lived_token)
    existing = fb_bridge_channel_for_page(page_id)

    if existing
      attrs = (existing.additional_attributes || {}).stringify_keys.merge(channel_attrs)
      existing.update!(
        additional_attributes: attrs,
        facebook_identity_id: facebook_identity_id.presence || existing.facebook_identity_id
      )
      inbox = existing.inbox
      action = 'updated'
    else
      channel = Current.account.api_channels.create!(
        webhook_url: '',
        hmac_mandatory: false,
        facebook_identity_id: facebook_identity_id,
        additional_attributes: channel_attrs
      )
      inbox = Current.account.inboxes.create!(name: page_name, channel: channel)
      inbox.add_members([current_user.id]) unless inbox.members.exists?(current_user.id)
      action = 'created'
    end

    {
      fb_page_id: page_id,
      inbox_id: inbox.id,
      name: inbox.name,
      action: action
    }
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
