# frozen_string_literal: true

# ADM4: session lifecycle for audited super-admin impersonation.
# Included in SuperAdmin::ApplicationController so EVERY console request
# checks the time-box. The marker lives in the super-admin Rails session;
# it is distinct, explicit and never silent:
#   session['patra_impersonation'] = { impersonator_id, target_user_id,
#                                      started_at, expires_at }
#   session[:impersonator_id]      = admin user id (required marker)
# Expired marker ⇒ auto-exit (audited best-effort) before the action runs.
# Frontend contract (DEFERRED-FRONTEND, documented in PATRA_FEAT_LOG.md):
#   - header  X-Patra-Impersonation on every console response while active
#   - GET /super_admin/patra_impersonation → JSON status for the SPA banner
module PatraImpersonationGuard
  extend ActiveSupport::Concern

  SESSION_KEY = 'patra_impersonation'
  TIME_BOX = 30.minutes

  included do
    before_action :expire_patra_impersonation!
    after_action :set_patra_impersonation_header
    helper_method :patra_impersonation, :patra_impersonation_active?
  end

  private

  def patra_impersonation
    data = session[SESSION_KEY]
    data.respond_to?(:to_h) && data.present? ? data.to_h.with_indifferent_access : nil
  end

  def patra_impersonation_active?
    patra_impersonation.present?
  end

  def start_patra_impersonation!(target_user)
    session[SESSION_KEY] = {
      'impersonator_id' => current_super_admin.id,
      'target_user_id' => target_user.id,
      'started_at' => Time.current.iso8601,
      'expires_at' => TIME_BOX.from_now.iso8601
    }
    session[:impersonator_id] = current_super_admin.id
  end

  def clear_patra_impersonation!
    session.delete(SESSION_KEY)
    session.delete(:impersonator_id)
    session.delete('impersonator_id')
  end

  def patra_impersonation_expired?(data)
    expires_at = Time.zone.parse(data[:expires_at].to_s)
    expires_at.nil? || expires_at <= Time.current
  rescue ArgumentError, TypeError
    true # unparseable expiry — never allow an unbounded impersonation window
  end

  # Auto-exit on expiry. Audit is best-effort here (a broken audit row must
  # not brick every console request); manual enter/exit DO hard-fail on
  # audit errors — see SuperAdmin::PatraImpersonationsController.
  def expire_patra_impersonation!
    data = patra_impersonation
    return if data.blank?
    return unless patra_impersonation_expired?(data)

    begin
      Patra::AdminAudit.record(
        admin: current_super_admin,
        action: 'impersonation.auto_exit',
        target: User.find_by(id: data[:target_user_id]),
        reason: 'time-box expired',
        metadata: { started_at: data[:started_at], expires_at: data[:expires_at] },
        request: request
      )
    rescue StandardError => e
      Rails.logger.error("[PatraImpersonationGuard] auto-exit audit failed: #{e.class}: #{e.message}")
    end
    clear_patra_impersonation!
  end

  def set_patra_impersonation_header
    data = patra_impersonation
    return if data.blank?

    response.set_header(
      'X-Patra-Impersonation',
      "active; target_user_id=#{data[:target_user_id]}; expires_at=#{data[:expires_at]}"
    )
  end
end
