# frozen_string_literal: true

class Api::V1::Accounts::ApprovalRequestsController < Api::V1::Accounts::BaseController
  before_action :check_admin_authorization?
  before_action :set_request, only: [:approve, :reject]

  def index
    requests = Current.account.approval_requests.order(created_at: :desc).limit(50)
    render json: requests
  end

  def approve
    @request.approve!(current_user)
    render json: @request
  end

  def reject
    @request.reject!(current_user)
    render json: @request
  end

  private

  def set_request
    @request = Current.account.approval_requests.find(params[:id])
  end
end
