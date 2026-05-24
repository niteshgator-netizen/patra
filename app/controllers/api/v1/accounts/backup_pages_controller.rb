# frozen_string_literal: true

class Api::V1::Accounts::BackupPagesController < Api::V1::Accounts::BaseController
  before_action :fetch_page, only: [:show, :update, :destroy]

  def index
    render json: Current.account.backup_pages.ordered
  end

  def create
    page = Current.account.backup_pages.create!(page_params)
    render json: page, status: :created
  end

  def update
    @page.update!(page_params)
    render json: @page
  end

  def destroy
    @page.destroy!
    head :ok
  end

  def reorder
    Array(params[:order]).each_with_index do |id, index|
      Current.account.backup_pages.find(id).update!(position: index)
    end
    render json: Current.account.backup_pages.ordered
  end

  private

  def fetch_page
    @page = Current.account.backup_pages.find(params[:id])
  end

  def page_params
    params.permit(:platform, :page_id, :page_name, :access_token, :status, :position)
  end
end
