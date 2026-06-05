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
end
