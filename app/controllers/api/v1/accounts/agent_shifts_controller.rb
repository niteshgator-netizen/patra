# frozen_string_literal: true

class Api::V1::Accounts::AgentShiftsController < Api::V1::Accounts::BaseController
  def index
    shifts = Current.account.agent_shifts.includes(:user)
    shifts = shifts.where(user_id: params[:user_id]) if params[:user_id].present?
    render json: shifts
  end

  def create
    shift = Current.account.agent_shifts.create!(shift_params)
    render json: shift, status: :created
  end

  def update
    shift = Current.account.agent_shifts.find(params[:id])
    shift.update!(shift_params)
    render json: shift
  end

  def destroy
    Current.account.agent_shifts.find(params[:id]).destroy!
    head :ok
  end

  private

  def shift_params
    params.permit(:user_id, :day_of_week, :start_time, :end_time, :active)
  end
end
