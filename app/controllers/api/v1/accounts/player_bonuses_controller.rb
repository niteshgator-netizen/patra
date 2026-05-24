# frozen_string_literal: true

class Api::V1::Accounts::PlayerBonusesController < Api::V1::Accounts::BaseController
  def index
    bonuses = Current.account.player_bonuses
                     .where(contact_id: params[:contact_id])
                     .order(created_at: :desc)
                     .limit(50)
    render json: bonuses
  end

  def create
    bonus = Current.account.player_bonuses.create!(
      contact_id: params[:contact_id],
      game_slug: params[:game_slug],
      amount: params[:amount],
      reason: params[:reason],
      given_by_user: current_user
    )
    render json: bonus, status: :created
  end
end
