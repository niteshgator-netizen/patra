# frozen_string_literal: true

# Background backfill of historical Zernio messages for a newly-connected
# (or resync-requested) Zernio inbox.
#
# Enqueued by:
#   - Zernio::OauthService#complete_connect (auto-fires after a successful OAuth)
#   - Api::V1::Accounts::Patra::ChannelsController#resync (admin manual re-run)
#
# Best-effort — never re-raises so Sidekiq doesn't retry. Operators can
# always re-trigger via the resync endpoint if needed.
module Zernio
  class SyncHistoryJob < ApplicationJob
    queue_as :low

    def perform(account_id, inbox_id)
      result = Zernio::HistorySyncService.new(
        account_id: account_id,
        inbox_id: inbox_id
      ).sync!

      Rails.logger.info("[Zernio::SyncHistoryJob] completed inbox=#{inbox_id} result=#{result.inspect}")
    rescue StandardError => e
      Rails.logger.error(
        "[Zernio::SyncHistoryJob] failed account=#{account_id} inbox=#{inbox_id} " \
        "#{e.class}: #{e.message}"
      )
    end
  end
end
