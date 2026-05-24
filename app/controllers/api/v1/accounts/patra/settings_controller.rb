# frozen_string_literal: true

class Api::V1::Accounts::Patra::SettingsController < Api::V1::Accounts::BaseController
  before_action :check_admin_authorization?

  SETTING_KEYS = %w[
    business_hours reengage_days auto_resolve_hours webhook_url reengage_message
    cashout_approval_threshold round_robin_enabled round_robin_max_conversations
    keyword_tag_mapping onboarding_checklist onboarding_dismissed
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

  private

  def settings_response
    attrs = (Current.account.custom_attributes || {}).stringify_keys
    {
      business_hours: attrs['business_hours'],
      reengage_days: attrs['reengage_days'] || 7,
      auto_resolve_hours: attrs['auto_resolve_hours'] || 24,
      webhook_url: attrs['webhook_url'],
      reengage_message: attrs['reengage_message'],
      cashout_approval_threshold: attrs['cashout_approval_threshold'] || 500,
      round_robin_enabled: attrs.fetch('round_robin_enabled', true),
      round_robin_max_conversations: attrs['round_robin_max_conversations'] || 50,
      keyword_tag_mapping: attrs['keyword_tag_mapping']
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
      business_hours: [:start, :end, :timezone, { days: [], ranges: [] }],
      keyword_tag_mapping: {},
      onboarding_checklist: {}
    )
  end
end
