# frozen_string_literal: true

class Api::V1::Accounts::Patra::FacebookConnectController < Api::V1::Accounts::BaseController
  before_action :check_admin_authorization?
  before_action :validate_fb_connect_pages_limit!, only: [:fb_connect_pages]

  def fb_connect
    short_token = params.require(:access_token).to_s
    long_lived = Facebook::PatraGraphService.exchange_user_token(short_token)
    pages = Facebook::PatraGraphService.fetch_managed_pages(long_lived)

    render json: { pages: pages, user_access_token: long_lived }
  rescue ArgumentError, StandardError => e
    Rails.logger.error("[PatraFB] fb_connect failed: #{e.class}: #{e.message}")
    render json: { error: e.message }, status: :unprocessable_entity
  end

  def fb_connect_pages
    user_token = params.require(:user_access_token).to_s
    pages_param = params.require(:pages)
    raise ActionController::ParameterMissing, 'pages' unless pages_param.is_a?(Array)

    created = []
    ActiveRecord::Base.transaction do
      pages_param.each do |raw|
        page = raw.permit(:id, :name, :access_token).to_h
        next if page['id'].blank? || page['access_token'].blank?

        created << create_fb_api_inbox!(page, user_token)
      end
    end

    render json: { inboxes: created }
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

  def validate_fb_connect_pages_limit!
    pages_param = params[:pages]
    n = pages_param.is_a?(Array) ? pages_param.size : 0
    return if n.zero?

    limit = Current.account.usage_limits[:inboxes]
    return if Current.account.inboxes.count + n <= limit

    render_payment_required('Account limit exceeded. Upgrade to a higher plan')
  end

  def create_fb_api_inbox!(page, user_long_lived_token)
    page_id = page['id'].to_s
    page_name = page['name'].presence || "Facebook #{page_id}"

    long_page_token = Facebook::PatraGraphService.long_lived_page_access_token(page_id, user_long_lived_token)
    Facebook::PatraGraphService.subscribe_page_webhook(page_id, long_page_token)

    channel_attrs = fb_channel_attributes(page_id, long_page_token, user_long_lived_token)
    channel = Current.account.api_channels.create!(
      webhook_url: '',
      hmac_mandatory: false,
      additional_attributes: channel_attrs
    )

    inbox = Current.account.inboxes.create!(name: page_name, channel: channel)
    inbox.add_members([current_user.id]) unless inbox.members.exists?(current_user.id)

    { id: inbox.id, name: inbox.name, channel_id: channel.id }
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
