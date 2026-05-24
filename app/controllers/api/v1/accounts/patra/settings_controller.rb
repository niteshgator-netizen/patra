# frozen_string_literal: true

class Api::V1::Accounts::Patra::SettingsController < Api::V1::Accounts::BaseController
  before_action :check_admin_authorization?

  def show
    attrs = (Current.account.custom_attributes || {}).stringify_keys
    render json: {
      business_hours: attrs['business_hours'],
      reengage_days: attrs['reengage_days'] || 7
    }
  end

  def update
    attrs = (Current.account.custom_attributes || {}).stringify_keys

    if settings_params.key?(:business_hours)
      attrs['business_hours'] = settings_params[:business_hours].to_h.stringify_keys
    end

    if settings_params.key?(:reengage_days)
      attrs['reengage_days'] = settings_params[:reengage_days].to_i
    end

    Current.account.update!(custom_attributes: attrs)
    render json: {
      business_hours: attrs['business_hours'],
      reengage_days: attrs['reengage_days'] || 7
    }
  end

  private

  def settings_params
    params.permit(
      :reengage_days,
      business_hours: [:start, :end, :timezone, { days: [] }]
    )
  end
end
