# frozen_string_literal: true

class Api::V1::Accounts::OwnerStatsController < Api::V1::Accounts::BaseController
  before_action :ensure_account_administrator!

  def show
    render json: OwnerStats::Aggregator.new(Current.account).call
  end

  private

  def ensure_account_administrator!
    raise Pundit::NotAuthorizedError unless Current.account_user&.administrator?
  end
end
