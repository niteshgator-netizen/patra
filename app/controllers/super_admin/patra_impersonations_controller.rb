# frozen_string_literal: true

# ADM4: audited, time-boxed support-login (impersonation).
# Security model (full write-up in PATRA_FEAT_LOG.md → SECURITY-MODEL):
#   - super-admin only: devise gate inherited + explicit re-check in #create
#   - audit row BEFORE the session marker/SSO link exist; audit failure aborts
#   - required reason
#   - NEVER impersonates a super admin (audited refusal)
#   - 30-minute time-box enforced every console request (PatraImpersonationGuard)
#   - one-click exit (#destroy) — never gated by the kill-switch, always audited
#   - the SSO token/link is never persisted or logged anywhere
class SuperAdmin::PatraImpersonationsController < SuperAdmin::ApplicationController
  # patra-fix2 G2: shared kill-switch gate (redirect back + styled flash).
  # Exit (#destroy) stays intentionally ungated.
  include SuperAdmin::ConsoleActionsGate
  before_action :require_console_actions!, only: [:create]

  # Documented status contract for the SPA banner (DEFERRED-FRONTEND).
  def show
    data = patra_impersonation
    if data.blank?
      render json: { active: false }
      return
    end

    render json: {
      active: true,
      impersonator_id: data[:impersonator_id],
      target_user_id: data[:target_user_id],
      started_at: data[:started_at],
      expires_at: data[:expires_at]
    }
  end

  def create
    # Re-check at session creation, not just route level.
    unless current_super_admin.is_a?(SuperAdmin)
      return render plain: 'Super admin required.', status: :forbidden
    end

    reason = params[:reason].to_s.strip
    if reason.blank?
      return redirect_back(fallback_location: super_admin_root_path,
                           alert: 'A reason is required to impersonate.')
    end

    target = User.find(params[:user_id])
    if target.is_a?(SuperAdmin)
      Patra::AdminAudit.record(
        admin: current_super_admin, action: 'impersonation.denied_super_admin_target',
        target: target, reason: reason, request: request
      )
      return render plain: 'Refusing to impersonate a super admin.', status: :forbidden
    end

    # Audit BEFORE the session starts — if this raises, no marker, no link.
    Patra::AdminAudit.record(
      admin: current_super_admin,
      action: 'impersonation.start',
      target: target,
      reason: reason,
      metadata: { target_account_ids: target.account_ids, time_box_minutes: PatraImpersonationGuard::TIME_BOX / 60 },
      request: request
    )
    start_patra_impersonation!(target)

    # One-time SSO token (5-min Redis TTL, existing Chatwoot mechanism). The
    # link is handed to the browser only — never logged, never persisted.
    redirect_to target.generate_sso_link_with_impersonation, allow_other_host: true
  end

  # Exit is intentionally NOT behind the kill-switch: an operator must always
  # be able to end an impersonation, even if actions get disabled mid-session.
  def destroy
    data = patra_impersonation
    if data.blank?
      return redirect_to super_admin_root_path, alert: 'No active impersonation.'
    end

    started_at = begin
      Time.zone.parse(data[:started_at].to_s)
    rescue ArgumentError, TypeError
      nil
    end
    Patra::AdminAudit.record(
      admin: current_super_admin,
      action: 'impersonation.exit',
      target: User.find_by(id: data[:target_user_id]),
      reason: 'manual exit',
      metadata: { duration_seconds: started_at ? (Time.current - started_at).round : nil },
      request: request
    )
    clear_patra_impersonation!
    redirect_to super_admin_root_path,
                notice: 'Impersonation marker ended. Close any tabs where you were logged in as the user.'
  end
end
