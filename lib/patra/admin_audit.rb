# frozen_string_literal: true

module Patra
  # ADM5: the ONLY write path to patra_admin_audit_logs. Append-only by
  # contract — this module exposes no update or destroy API and the model
  # rejects both after persist. Call BEFORE performing the audited action so
  # a failed audit aborts the action (never the other way around).
  #
  #   Patra::AdminAudit.record(
  #     admin: current_super_admin, action: 'account.suspend',
  #     target: account, reason: params[:reason], metadata: { from: 'active' },
  #     request: request
  #   )
  module AdminAudit
    # Keys whose values must never be persisted, whatever they contain.
    SENSITIVE_KEY_RE = /(secret|password|passwd|credential|token|api[_-]?key|private[_-]?key|access[_-]?key|auth|session|cookie|otp)/i
    # Values that LOOK like secrets (long opaque hex/base64-ish blobs) get
    # masked even when they arrive under an innocent key.
    SENSITIVE_VALUE_RE = %r{\A[A-Za-z0-9+/=_\-.]{32,}\z}
    SCRUBBED = '[SCRUBBED]'

    module_function

    def record(admin:, action:, target: nil, reason: nil, metadata: {}, request: nil)
      PatraAdminAuditLog.create!(
        admin_user_id: admin&.id,
        action: action.to_s,
        target_type: target.is_a?(ActiveRecord::Base) ? target.class.base_class.name : nil,
        target_id: target.is_a?(ActiveRecord::Base) ? target.id : nil,
        reason: reason.presence,
        metadata: scrub(metadata || {}),
        ip_address: request.respond_to?(:remote_ip) ? request.remote_ip : nil
      )
    end

    # Deep-scrubs hashes/arrays. Never raises on weird input — auditing must
    # not crash the action being audited, so unknown scalars pass through.
    def scrub(value)
      case value
      when Hash
        value.each_with_object({}) do |(key, val), out|
          out[key.to_s] = SENSITIVE_KEY_RE.match?(key.to_s) ? SCRUBBED : scrub(val)
        end
      when Array
        value.map { |item| scrub(item) }
      when String
        SENSITIVE_VALUE_RE.match?(value) ? SCRUBBED : value
      else
        value
      end
    end
  end
end
