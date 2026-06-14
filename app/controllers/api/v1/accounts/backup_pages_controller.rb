# frozen_string_literal: true

class Api::V1::Accounts::BackupPagesController < Api::V1::Accounts::BaseController
  include Patra::MainFeatureGuard

  before_action :fetch_page, only: [:show, :update, :destroy]
  # Backup pages hold page access tokens (ban-recovery infra) — mutations are owner / granted-manager only.
  before_action(only: [:create, :update, :destroy, :reorder, :drip_config]) { check_main_feature_authorization!(:backup_pages) }

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

  # B-COVERAGE — read-only coverage stats (% fully connected, breakdown, per-page counts). Like
  # #index, readable by any account member; reveals no page access tokens.
  def coverage
    render json: Backup::CoverageStats.new(Current.account).call
  end

  # B-DRIP config — owner/granted-manager only (guarded above). Sets the per-account drip toggle,
  # invite wording and cadence in account.custom_attributes (free-form — never billing settings).
  # The actual SENDING stays hard-gated by ENV['PATRA_BACKUP_DRIP_ENABLED'] regardless of this.
  def drip_config
    permitted = params.permit(:backup_invite_message, :backup_drip_enabled, :backup_drip_cadence_days)
    attrs = Current.account.custom_attributes || {}

    attrs['backup_invite_message'] = permitted[:backup_invite_message].to_s if permitted.key?(:backup_invite_message)
    if permitted.key?(:backup_drip_enabled)
      attrs['backup_drip_enabled'] = ActiveModel::Type::Boolean.new.cast(permitted[:backup_drip_enabled])
    end
    if permitted.key?(:backup_drip_cadence_days)
      cadence = permitted[:backup_drip_cadence_days].to_i
      attrs['backup_drip_cadence_days'] =
        Backup::ConnectUpDrip::ALLOWED_CADENCES.include?(cadence) ? cadence : Backup::ConnectUpDrip::DEFAULT_CADENCE_DAYS
    end

    Current.account.update!(custom_attributes: attrs)
    render json: drip_config_view(attrs)
  end

  private

  def fetch_page
    @page = Current.account.backup_pages.find(params[:id])
  end

  def page_params
    params.permit(:platform, :page_id, :page_name, :access_token, :status, :position, :role, :inbox_id)
  end

  def drip_config_view(attrs)
    {
      backup_invite_message: attrs['backup_invite_message'],
      backup_drip_enabled: attrs['backup_drip_enabled'] || false,
      backup_drip_cadence_days: attrs['backup_drip_cadence_days'] || Backup::ConnectUpDrip::DEFAULT_CADENCE_DAYS,
      # The ops-level master kill switch. When false, NO drip send happens regardless of the toggle.
      drip_master_enabled: ENV['PATRA_BACKUP_DRIP_ENABLED'].to_s == 'true'
    }
  end
end
