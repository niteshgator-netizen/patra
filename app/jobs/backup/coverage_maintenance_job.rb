# frozen_string_literal: true

module Backup
  # Patra (B-CONN + B-DRIP) — hourly coverage maintenance. Records connections from recent inbound
  # (idempotent), then runs the connect-up drip. The drip is DARK by default — Backup::ConnectUpDrip
  # no-ops unless PATRA_BACKUP_DRIP_ENABLED='true' AND the per-account toggle is on — so on a default
  # install this job only refreshes the coverage ledger and sends nothing.
  class CoverageMaintenanceJob < ApplicationJob
    queue_as :scheduled_jobs

    def perform
      Account.find_each do |account|
        Backup::ConnectionRecorder.new(account).sweep
        Backup::ConnectUpDrip.new(account).run
      rescue StandardError => e
        Rails.logger.error("[Backup::CoverageMaintenanceJob] account=#{account.id} failed: #{e.class}: #{e.message}")
      end
    end
  end
end
