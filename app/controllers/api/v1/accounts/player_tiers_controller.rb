# frozen_string_literal: true

class Api::V1::Accounts::PlayerTiersController < Api::V1::Accounts::BaseController
  before_action :set_player_tier, only: [:show, :update, :destroy]

  def index
    @player_tiers = Current.account.player_tiers.ordered
    render json: @player_tiers
  end

  def create
    @player_tier = Current.account.player_tiers.new(player_tier_params)
    if @player_tier.save
      render json: @player_tier, status: :created
    else
      render json: { errors: @player_tier.errors.full_messages }, status: :unprocessable_entity
    end
  end

  def show
    render json: @player_tier
  end

  def update
    if @player_tier.update(player_tier_params)
      render json: @player_tier
    else
      render json: { errors: @player_tier.errors.full_messages }, status: :unprocessable_entity
    end
  end

  def destroy
    @player_tier.destroy!
    head :no_content
  end

  # POST /api/v1/accounts/:account_id/contacts/bulk_tier
  def bulk_assign
    contact_ids = params[:contact_ids]
    tier_id = params[:player_tier_id]

    if contact_ids.blank?
      render json: { error: 'contact_ids required' }, status: :unprocessable_entity
      return
    end

    updated = Current.account.contacts.where(id: contact_ids).update_all(player_tier_id: tier_id)
    render json: { updated: updated }
  end

  private

  def set_player_tier
    @player_tier = Current.account.player_tiers.find(params[:id])
  end

  def player_tier_params
    params.require(:player_tier).permit(
      :name, :color, :badge_text, :sort_order,
      :auto_promote_after_deposits, :auto_promote_deposit_threshold,
      rule_overrides: {}
    )
  end
end
