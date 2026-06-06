# frozen_string_literal: true

class Api::V1::Accounts::GameRulesController < Api::V1::Accounts::BaseController
  before_action :set_game_rule, only: [:show, :update]

  def index
    @game_rules = Current.account.game_rules.includes(:game)
    render json: @game_rules.as_json(include: { game: { only: [:id, :name, :slug] } })
  end

  def show
    render json: @game_rule.as_json(include: { game: { only: [:id, :name, :slug] } })
  end

  def update
    if @game_rule.update(game_rule_params)
      render json: @game_rule.as_json(include: { game: { only: [:id, :name, :slug] } })
    else
      render json: { errors: @game_rule.errors.full_messages }, status: :unprocessable_entity
    end
  end

  private

  def set_game_rule
    @game_rule = Current.account.game_rules.find_or_initialize_by(game_id: params[:game_id])
  end

  def game_rule_params
    params.require(:game_rule).permit(
      :freeplay_enabled, :freeplay_amount, :freeplay_max_per_day, :freeplay_max_per_week,
      :freeplay_eligible_tiers, :freeplay_cashout_min_multiplier, :freeplay_cashout_max_amount,
      :freeplay_require_deposit_first, :freeplay_message,
      :deposit_bonus_enabled, :deposit_bonus_percentage, :deposit_bonus_min_amount,
      :deposit_bonus_max_bonus, :deposit_bonus_eligible_tiers, :deposit_bonus_first_deposit_only,
      :deposit_bonus_message,
      :cashout_enabled, :cashout_min_multiplier, :cashout_max_multiplier,
      :cashout_max_amount, :cashout_min_amount, :cashout_freeplay_multiplier,
      :cashout_freeplay_max, :cashout_rules_text, :cashout_require_screenshot,
      :game_download_url, :game_web_url, :auto_send_link_on_create, :game_info_message
    )
  end
end
