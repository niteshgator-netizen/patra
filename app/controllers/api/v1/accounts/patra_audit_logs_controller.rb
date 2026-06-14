# frozen_string_literal: true

class Api::V1::Accounts::PatraAuditLogsController < Api::V1::Accounts::BaseController
  before_action :check_admin_authorization?

  def index
    logs = Current.account.audit_logs.order(created_at: :desc)
    # SEC — per-agent activity viewer: optional filters by member and action (e.g. 'deception_flag').
    logs = logs.where(user_id: params[:user_id]) if params[:user_id].present?
    logs = logs.where(action: params[:action_type]) if params[:action_type].present?
    render json: logs.limit(page_limit).map { |log| serialize(log) }
  end

  private

  # Default 100, caller-configurable up to 500.
  def page_limit
    raw = params[:limit].to_i
    raw.positive? ? [raw, 500].min : 100
  end

  def serialize(log)
    {
      id: log.id,
      action: log.action,
      user_id: log.user_id,
      target_type: log.target_type,
      target_id: log.target_id,
      metadata: log.metadata,
      ip_address: log.ip_address,
      created_at: log.created_at
    }
  end
end
