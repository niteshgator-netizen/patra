# frozen_string_literal: true

class Api::V1::Accounts::GameActionsController < Api::V1::Accounts::BaseController
  def index
    actions = Current.account.game_actions.order(created_at: :desc).limit(50)
    actions = actions.where(contact_id: params[:contact_id]) if params[:contact_id].present?
    actions = actions.where(action_type: params[:action_type]) if params[:action_type].present?
    render json: actions
  end
end
