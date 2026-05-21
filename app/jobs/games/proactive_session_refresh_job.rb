# Proactive session refresh for Cluster 1 (ASP.NET) and Cluster 2 (Laravel) panels.
# Runs every 4 hours via sidekiq-cron. Refreshes sessions BEFORE they expire,
# so customer-facing requests don't incur reactive-refresh latency.
#
# Reactive refresh (Ship 3, in BaseClient#http_request) remains the safety net
# for any session that dies between cron cycles.
#
# Shipped May 21 2026 (Ship 4).
module Games
  class ProactiveSessionRefreshJob < ApplicationJob
    queue_as :low

    CLUSTER_1_SLUGS = %w[milky_way fire_kirin panda_master orion_stars].freeze
    CLUSTER_2_SLUGS = %w[mafia game_room cash_machine mr_all_in_one].freeze
    REFRESHABLE_SLUGS = (CLUSTER_1_SLUGS + CLUSTER_2_SLUGS).freeze

    def perform
      Rails.logger.info("[ProactiveRefresh] starting cycle at #{Time.now.utc}")
      ok_count = 0
      fail_count = 0
      skip_count = 0
      details = []

      AgentGame.joins(:game).where(games: { slug: REFRESHABLE_SLUGS }).find_each do |ag|
        slug = ag.game.slug
        creds = ag.credentials.to_h

        if creds.blank? || creds['agent_username'].to_s.empty? || creds['agent_password'].to_s.empty?
          skip_count += 1
          details << "#{slug}: skipped (creds incomplete)"
          next
        end

        begin
          ag.with_lock do
            ag.reload
            result = if CLUSTER_1_SLUGS.include?(slug)
                       Games::AspNetPanel::SessionRefresher.new(ag).refresh!(interactive: false)
                     else
                       Games::LaravelPanel::SessionRefresher.new(ag).refresh!
                     end

            if result.is_a?(Hash) && result[:ok]
              ok_count += 1
              details << "#{slug}: ok"
              Rails.logger.info("[ProactiveRefresh][#{slug}] ✅")
            else
              fail_count += 1
              err = result.is_a?(Hash) ? (result[:error] || result.inspect) : result.inspect
              details << "#{slug}: FAILED — #{err.to_s[0, 100]}"
              Rails.logger.warn("[ProactiveRefresh][#{slug}] ❌ #{err}")
            end
          end
        rescue StandardError => e
          fail_count += 1
          details << "#{slug}: RAISED — #{e.class}: #{e.message[0, 100]}"
          Rails.logger.error("[ProactiveRefresh][#{slug}] 💥 #{e.class}: #{e.message}")
        end
      end

      Rails.logger.info("[ProactiveRefresh] DONE: ok=#{ok_count} fail=#{fail_count} skipped=#{skip_count}")
      Rails.logger.info("[ProactiveRefresh] details: #{details.join(' | ')}")
    end
  end
end
