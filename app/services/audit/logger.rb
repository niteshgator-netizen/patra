# frozen_string_literal: true

module Audit
  class Logger
    def self.log!(account:, action:, user: nil, target: nil, metadata: {}, ip_address: nil)
      AuditLog.create!(
        account: account,
        user: user,
        action: action,
        target_type: target&.class&.name,
        target_id: target&.id,
        metadata: metadata,
        ip_address: ip_address || Current.ip_address
      )
    rescue StandardError => e
      Rails.logger.error("[Audit::Logger] failed action=#{action}: #{e.class}: #{e.message}")
      nil
    end
  end
end
