# frozen_string_literal: true

class Api::V1::Accounts::PatraAuditLogsController < Api::V1::Accounts::BaseController
  before_action :check_admin_authorization?

  def index
    logs = Current.account.audit_logs.order(created_at: :desc).limit(100)
    render json: logs.map { |log| serialize(log) }
  end

  private

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
