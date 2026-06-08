# frozen_string_literal: true

class Api::V1::Accounts::ReferralsController < Api::V1::Accounts::BaseController
  before_action :set_referral, only: [:update]

  def index
    @referrals = Current.account.referrals.includes(:referrer_contact, :referred_contact)
                        .order(created_at: :desc)
                        .page(params[:page])
    render json: @referrals
  end

  def create
    @referral = Current.account.referrals.new(referral_params)
    if @referral.save
      render json: @referral, status: :created
    else
      render json: { errors: @referral.errors.full_messages }, status: :unprocessable_entity
    end
  end

  def update
    if @referral.update(referral_params)
      render json: @referral
    else
      render json: { errors: @referral.errors.full_messages }, status: :unprocessable_entity
    end
  end

  # GET /api/v1/accounts/:account_id/referrals/settings
  # Referral SETTINGS live on the account's reply_preference row (one per account).
  def settings
    @pref = ReplyPreference.for_account(Current.account.id)
    render json: referral_settings_json(@pref)
  end

  # PUT /api/v1/accounts/:account_id/referrals/settings
  def update_settings
    @pref = ReplyPreference.for_account(Current.account.id)
    if @pref.update(referral_settings_params)
      render json: referral_settings_json(@pref)
    else
      render json: { errors: @pref.errors.full_messages }, status: :unprocessable_entity
    end
  end

  private

  def set_referral
    @referral = Current.account.referrals.find(params[:id])
  end

  def referral_params
    params.require(:referral).permit(
      :referrer_contact_id, :referred_contact_id,
      :status, :bonus_amount, :bonus_type
    )
  end

  def referral_settings_params
    params.require(:referral_settings).permit(
      :referral_enabled,
      :referral_bonus_referrer,
      :referral_bonus_new_player,
      :referral_bonus_type,
      :referral_require_deposit,
      :referral_tracking_method,
      :referral_message_referrer,
      :referral_message_new_player
    )
  end

  def referral_settings_json(pref)
    {
      referral_enabled: pref.referral_enabled,
      referral_bonus_referrer: pref.referral_bonus_referrer,
      referral_bonus_new_player: pref.referral_bonus_new_player,
      referral_bonus_type: pref.referral_bonus_type,
      referral_require_deposit: pref.referral_require_deposit,
      referral_tracking_method: pref.referral_tracking_method,
      referral_message_referrer: pref.referral_message_referrer,
      referral_message_new_player: pref.referral_message_new_player
    }
  end
end
