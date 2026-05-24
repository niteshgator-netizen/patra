# frozen_string_literal: true

class Api::V1::Accounts::Patra::HolidaysController < Api::V1::Accounts::BaseController
  before_action :check_admin_authorization?

  def index
    holidays = Current.account.holidays.order(:closed_on)
    render json: holidays
  end

  def create
    holiday = Current.account.holidays.create!(holiday_params)
    render json: holiday, status: :created
  end

  def destroy
    Current.account.holidays.find(params[:id]).destroy!
    head :ok
  end

  private

  def holiday_params
    params.permit(:closed_on, :name, :inbox_id)
  end
end
