# frozen_string_literal: true

class Api::V1::Accounts::DripCampaignsController < Api::V1::Accounts::BaseController
  before_action :fetch_campaign, only: [:show, :update, :destroy, :activate]

  def index
    render json: Current.account.drip_campaigns.includes(:automation_flow)
  end

  def create
    campaign = Current.account.drip_campaigns.create!(campaign_params)
    render json: campaign, status: :created
  end

  def update
    @campaign.update!(campaign_params)
    render json: @campaign
  end

  def destroy
    @campaign.destroy!
    head :ok
  end

  def activate
    @campaign.update!(status: 'active')
    Drip::ProcessCampaignJob.perform_later(@campaign.id)
    render json: @campaign
  end

  private

  def fetch_campaign
    @campaign = Current.account.drip_campaigns.find(params[:id])
  end

  def campaign_params
    params.permit(:automation_flow_id, :status, :scheduled_at, contact_segment: {})
  end
end
