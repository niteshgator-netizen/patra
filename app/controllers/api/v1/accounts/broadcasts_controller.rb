# frozen_string_literal: true

class Api::V1::Accounts::BroadcastsController < Api::V1::Accounts::BaseController
  before_action :fetch_broadcast, only: [:show, :update, :destroy, :send_now, :preview_count]

  def index
    broadcasts = Current.account.broadcasts.order(created_at: :desc)
    render json: broadcasts
  end

  def show
    render json: @broadcast
  end

  def create
    broadcast = Current.account.broadcasts.create!(broadcast_params.merge(created_by_user: current_user))
    render json: broadcast, status: :created
  end

  def update
    @broadcast.update!(broadcast_params)
    render json: @broadcast
  end

  def destroy
    @broadcast.destroy!
    head :ok
  end

  def send_now
    @broadcast.update!(status: 'scheduled', scheduled_at: Time.current)
    Broadcasts::SendBroadcastJob.perform_later(@broadcast.id)
    render json: @broadcast
  end

  def preview_count
    count = Contacts::SegmentFilter.new(Current.account, @broadcast.segment_filter).count
    render json: { count: count }
  end

  private

  def fetch_broadcast
    @broadcast = Current.account.broadcasts.find(params[:id])
  end

  def broadcast_params
    params.permit(:name, :channel, :content, :media_url, :status, :scheduled_at, segment_filter: {})
  end
end
