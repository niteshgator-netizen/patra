# frozen_string_literal: true

class Api::V1::Accounts::OwnerStatsController < Api::V1::Accounts::BaseController
  before_action :check_authorization

  def show
    render json: OwnerStats::Aggregator.new(Current.account).call
  end

  private

  def check_authorization
    authorize :report, :view?
  end
end
