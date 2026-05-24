# frozen_string_literal: true

class Api::V1::Accounts::CashierClaimsController < Api::V1::Accounts::BaseController
  before_action :fetch_claim, only: [:claim, :complete]

  def index
    claims = Current.account.cashier_claims.pending.order(created_at: :asc)
    render json: claims
  end

  def claim
    if @claim.claim!(current_user)
      render json: @claim
    else
      render json: { error: 'Already claimed' }, status: :unprocessable_entity
    end
  end

  def complete
    @claim.complete!
    render json: @claim
  end

  private

  def fetch_claim
    @claim = Current.account.cashier_claims.find(params[:id])
  end
end
