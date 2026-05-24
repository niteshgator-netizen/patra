# frozen_string_literal: true

class Api::V1::Accounts::Patra::SettingsController < Api::V1::Accounts::BaseController
  before_action :check_admin_authorization?

  DEFAULT_REENGAGE_MESSAGE = 'hey! been a minute 🎰 got any new games you wanna try?'

  DEFAULT_KEYWORD_TAG_MAPPING = {
    'angry-customer' => ['angry'],
    'refund-request' => ['refund'],
    'technical-issue' => ['not working']
  }.freeze

  SETTING_KEYS = %w[
    business_hours reengage_days auto_resolve_hours webhook_url reengage_message
    cashout_approval_threshold round_robin_enabled round_robin_max_conversations
    keyword_tag_mapping onboarding_checklist onboarding_dismissed
    first_response_limit_minutes resolution_limit_minutes sla_alerts_enabled
  ].freeze

  def show
    render json: settings_response
  end

  def update
    attrs = (Current.account.custom_attributes || {}).stringify_keys

    if settings_params.key?(:business_hours)
      attrs['business_hours'] = settings_params[:business_hours].to_h.stringify_keys
    end

    SETTING_KEYS.each do |key|
      next unless settings_params.key?(key.to_sym)

      attrs[key] = settings_params[key.to_sym]
    end

    Current.account.update!(custom_attributes: attrs)
    render json: settings_response
  end

  def test_webhook
    url = (Current.account.custom_attributes || {}).stringify_keys['webhook_url'].to_s.presence
    if url.blank?
      return render json: { ok: false, error: I18n.t('patra.settings.webhook_url_blank') }, status: :unprocessable_entity
    end

    body = {
      event: 'webhook.test',
      account_id: Current.account.id,
      timestamp: Time.current.iso8601,
      data: { message: I18n.t('patra.settings.webhook_test_payload') }
    }

    response = HTTParty.post(url, body: body.to_json, headers: { 'Content-Type' => 'application/json' }, timeout: 10)
    if response.success?
      render json: { ok: true, message: I18n.t('patra.settings.webhook_test_success'), status: response.code }
    else
      render json: {
        ok: false,
        error: I18n.t('patra.settings.webhook_test_failed', status: response.code),
        status: response.code
      }, status: :unprocessable_entity
    end
  rescue StandardError => e
    render json: { ok: false, error: e.message }, status: :unprocessable_entity
  end

  private

  def settings_response
    attrs = (Current.account.custom_attributes || {}).stringify_keys
    {
      business_hours: attrs['business_hours'],
      reengage_days: attrs['reengage_days'] || 7,
      auto_resolve_hours: attrs['auto_resolve_hours'] || 24,
      webhook_url: attrs['webhook_url'],
      reengage_message: attrs['reengage_message'].presence || DEFAULT_REENGAGE_MESSAGE,
      cashout_approval_threshold: attrs['cashout_approval_threshold'] || 500,
      round_robin_enabled: attrs.fetch('round_robin_enabled', true),
      round_robin_max_conversations: attrs['round_robin_max_conversations'] || 50,
      keyword_tag_mapping: attrs['keyword_tag_mapping'].presence || DEFAULT_KEYWORD_TAG_MAPPING,
      first_response_limit_minutes: attrs['first_response_limit_minutes'] || 5,
      resolution_limit_minutes: attrs['resolution_limit_minutes'] || 60,
      sla_alerts_enabled: attrs.fetch('sla_alerts_enabled', true)
    }
  end

  def settings_params
    params.permit(
      :reengage_days,
      :auto_resolve_hours,
      :webhook_url,
      :reengage_message,
      :cashout_approval_threshold,
      :round_robin_enabled,
      :round_robin_max_conversations,
      :first_response_limit_minutes,
      :resolution_limit_minutes,
      :sla_alerts_enabled,
      business_hours: [:start, :end, :timezone, { days: [], ranges: [] }],
      keyword_tag_mapping: {},
      onboarding_checklist: {}
    )
  end
end
