# frozen_string_literal: true

# PATRA TAB-C (ADM6): platform banner posting is an explicit, audited action.
# Nothing auto-posts — banners only change through these Administrate actions,
# and every create/update/destroy writes an ADM5 audit row (the row records
# the attempt; Administrate then performs the mutation).
class SuperAdmin::PlatformBannersController < SuperAdmin::ApplicationController
  before_action :ensure_chatwoot_cloud
  before_action :audit_banner_mutation, only: [:create, :update, :destroy]

  private

  def ensure_chatwoot_cloud
    raise ActionController::RoutingError, 'Not Found' unless ChatwootApp.chatwoot_cloud?
  end

  def audit_banner_mutation
    Patra::AdminAudit.record(
      admin: current_super_admin,
      action: "platform_banner.#{action_name}",
      target: action_name == 'create' ? nil : requested_resource,
      reason: banner_params_for_audit['banner_message'].to_s.truncate(150).presence || "banner #{action_name}",
      metadata: { attributes: banner_params_for_audit },
      request: request
    )
  end

  def banner_params_for_audit
    params.fetch(:platform_banner, ActionController::Parameters.new)
          .permit(:banner_message, :banner_type, :active).to_h
  end
end
