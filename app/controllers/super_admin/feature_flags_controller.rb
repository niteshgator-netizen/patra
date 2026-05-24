# frozen_string_literal: true

class SuperAdmin::FeatureFlagsController < SuperAdmin::ApplicationController
  def index
    render json: FeatureFlag.all
  end

  def create
    flag = FeatureFlag.create!(flag_params)
    render json: flag, status: :created
  end

  def update
    flag = FeatureFlag.find(params[:id])
    flag.update!(flag_params)
    render json: flag
  end

  private

  def flag_params
    params.permit(:name, :description, :enabled_globally, :percentage_rollout, enabled_for_accounts: [])
  end
end
