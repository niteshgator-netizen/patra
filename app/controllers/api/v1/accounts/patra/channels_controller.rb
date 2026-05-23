# frozen_string_literal: true

# Multi-channel connect endpoints for Patra customers using Zernio's
# headless OAuth.
#
# Routes (mounted inside the patra namespace at /api/v1/accounts/:account_id/patra):
#
#   GET  /channels
#     Lists every inbox on the account with platform metadata + live status.
#     Open to any account user — agents need this for the sidebar.
#
#   POST /channels/connect       (admin-only)
#     Body: { platform: 'facebook'|'instagram'|'whatsapp'|'telegram',
#             redirect_url: <optional> }
#     Returns: { auth_url:, state:, zernio_profile_id: }
#     Frontend redirects the user to auth_url; Zernio handles OAuth and
#     calls back to redirect_url with the connected account params.
#
#   POST /channels/complete      (admin-only)
#     Body: { platform:, zernio_account_id:, page_name:, page_username:? }
#     Idempotent — reuses an existing Channel::Api/Inbox if the same
#     zernio_account_id is already connected to this account.
#     Returns: { success: true, inbox_id:, message: ... }
#
#   POST /channels/:id/resync    (admin-only)
#     Re-triggers Zernio::SyncHistoryJob for a given Zernio inbox.
class Api::V1::Accounts::Patra::ChannelsController < Api::V1::Accounts::BaseController
  # `index` is read-only and needed by the agent sidebar; the other actions
  # mutate state (create channels, kick off background sync) so they're gated
  # to admins per the existing Patra::FacebookConnectController pattern.
  before_action :check_admin_authorization?, only: [:connect, :complete, :resync]

  def index
    inboxes = Current.account.inboxes.includes(:channel).order(:name)
    render json: { channels: inboxes.map { |inbox| channel_info(inbox) } }
  end

  def connect
    result = Zernio::OauthService.new(Current.account).connect_url(
      platform: params.require(:platform).to_s,
      redirect_url: params[:redirect_url].presence || default_redirect_url
    )

    render json: result
  rescue ArgumentError => e
    render json: { error: e.message }, status: :unprocessable_entity
  rescue StandardError => e
    Rails.logger.error("[Patra::Channels] connect failed account=#{Current.account.id} #{e.class}: #{e.message}")
    render json: { error: e.message }, status: :unprocessable_entity
  end

  def complete
    inbox = Zernio::OauthService.new(Current.account).complete_connect(
      platform: params.require(:platform).to_s,
      zernio_account_id: params.require(:zernio_account_id).to_s,
      page_name: params.require(:page_name).to_s,
      page_username: params[:page_username].presence
    )

    render json: {
      success: true,
      inbox_id: inbox.id,
      messaging_provider: inbox.messaging_provider,
      message: "#{inbox.name} connected. Syncing message history in the background."
    }
  rescue ArgumentError => e
    render json: { error: e.message }, status: :unprocessable_entity
  rescue ActiveRecord::RecordInvalid => e
    Rails.logger.error("[Patra::Channels] complete validation account=#{Current.account.id} #{e.message}")
    render json: { error: e.message }, status: :unprocessable_entity
  rescue StandardError => e
    Rails.logger.error("[Patra::Channels] complete failed account=#{Current.account.id} #{e.class}: #{e.message}")
    render json: { error: e.message }, status: :unprocessable_entity
  end

  def resync
    inbox = Current.account.inboxes.find(params[:id])

    unless inbox.messaging_provider == 'zernio'
      return render(
        json: { error: 'Inbox is not a Zernio inbox; resync only applies to Zernio-connected channels.' },
        status: :unprocessable_entity
      )
    end

    # Guard so the controller doesn't NameError during the gap between
    # H.3 deploy and H.4 (Zernio::SyncHistoryJob) deploy.
    unless defined?(Zernio::SyncHistoryJob)
      return render(
        json: { error: 'History sync is not yet available on this deploy.' },
        status: :service_unavailable
      )
    end

    Zernio::SyncHistoryJob.perform_later(Current.account.id, inbox.id)
    render json: { success: true, message: 'History sync queued.' }
  end

  private

  def channel_info(inbox)
    channel = inbox.channel
    attrs = channel.respond_to?(:additional_attributes) ? channel.additional_attributes.to_h : {}

    {
      id: inbox.id,
      name: inbox.name,
      channel_type: inbox.channel_type,
      messaging_provider: inbox.messaging_provider,
      platform: derive_platform(inbox, attrs),
      status: inbox_status(inbox),
      conversations_count: inbox.conversations.count,
      created_at: inbox.created_at
    }
  end

  # For Zernio inboxes the underlying platform is stashed on the channel as
  # `zernio_platform` (set during OAuth complete, or backfilled by Phase G's
  # InboundDispatcher write-once persistence). For native channels we fall
  # back to channel_type → human label; for direct-Meta BYOC inboxes
  # (Channel::Api with fb_page_id) we report 'facebook'.
  def derive_platform(inbox, attrs)
    return attrs['zernio_platform'] if inbox.messaging_provider == 'zernio' && attrs['zernio_platform'].present?

    case inbox.channel_type
    when 'Channel::FacebookPage' then 'facebook'
    when 'Channel::Instagram' then 'instagram'
    when 'Channel::TwitterProfile' then 'twitter'
    when 'Channel::Telegram' then 'telegram'
    when 'Channel::Whatsapp' then 'whatsapp'
    when 'Channel::TwilioSms' then 'sms'
    when 'Channel::Sms' then 'sms'
    when 'Channel::Email' then 'email'
    when 'Channel::WebWidget' then 'web'
    when 'Channel::Tiktok' then 'tiktok'
    when 'Channel::Line' then 'line'
    when 'Channel::Api'
      attrs['fb_page_id'].present? ? 'facebook' : 'api'
    else 'unknown'
    end
  end

  # 'live' = any message (incoming or outgoing) in the last 24h on this inbox.
  # Uses messages.inbox_id index + messages.created_at index, no join.
  def inbox_status(inbox)
    inbox.messages.where('created_at > ?', 24.hours.ago).exists? ? 'live' : 'idle'
  end

  def default_redirect_url
    "#{ENV.fetch('FRONTEND_URL', 'https://patrahq.com').to_s.chomp('/')}/app/accounts/#{Current.account.id}/settings/inboxes/new"
  end
end
