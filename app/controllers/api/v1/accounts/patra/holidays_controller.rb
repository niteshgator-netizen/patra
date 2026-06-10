# frozen_string_literal: true

class Api::V1::Accounts::Patra::HolidaysController < Api::V1::Accounts::BaseController
  before_action :check_admin_authorization?

  def index
    holidays = Current.account.holidays.order(:closed_on)
    render json: holidays
  end

  def create
    attrs = holiday_params
    if attrs[:inbox_id].present? && !Current.account.inboxes.exists?(attrs[:inbox_id])
      return render json: { error: 'inbox does not belong to this account' }, status: :unprocessable_entity
    end

    holiday = Current.account.holidays.create!(attrs)
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
