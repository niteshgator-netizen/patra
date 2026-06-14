# frozen_string_literal: true

module Backup
  # Patra (B-COVERAGE) — read-only coverage math over the connection ledger.
  #
  # "Live" pages = not banned/retired, so a banned page simply drops out of the universe and every
  # percentage recomputes with NO migration. "Fully connected" = a customer linked to EVERY live
  # backup. The pure math lives in .compute so it is unit-testable without a DB; #call only does the
  # ActiveRecord queries that feed it.
  class CoverageStats
    def initialize(account)
      @account = account
    end

    def call
      live = @account.backup_pages.live.ordered.to_a
      main = live.find(&:main?)
      backups = live.reject(&:main?)
      backup_ids = backups.map(&:id)

      customer_ids = customer_ids_for(main)
      backup_counts = backup_counts_for(customer_ids, backup_ids)
      customer_backup_counts = customer_ids.index_with { |cid| backup_counts[cid].to_i }
      page_counts = page_connection_counts(live.map(&:id))

      self.class.compute(live_backup_count: backup_ids.size, customer_backup_counts: customer_backup_counts).merge(
        has_main: main.present?,
        live_pages: live.size,
        per_page: live.map do |p|
          { id: p.id, page_name: p.page_name, role: p.role, status: p.status, connections: page_counts[p.id].to_i }
        end,
        next_drip_estimate: next_drip_estimate
      )
    end

    # Pure function: customer_backup_counts is { contact_id => number_of_live_backups_connected }
    # for EVERY customer (those with zero backups included as the "main only" bucket).
    def self.compute(live_backup_count:, customer_backup_counts:)
      total = customer_backup_counts.size
      histogram = Hash.new(0)
      customer_backup_counts.each_value { |n| histogram[n] += 1 }

      fully = live_backup_count.positive? ? customer_backup_counts.count { |_, n| n >= live_backup_count } : 0

      {
        total_customers: total,
        live_backups: live_backup_count,
        fully_connected: fully,
        fully_connected_pct: total.zero? ? 0.0 : ((fully.to_f / total) * 100).round(1),
        incomplete_count: total - fully,
        breakdown: {
          all: fully,
          three_backups: histogram[3],
          two_backups: histogram[2],
          one_backup: histogram[1],
          main_only: histogram[0]
        },
        by_backups_connected: histogram.keys.sort.index_with { |k| histogram[k] }
      }
    end

    private

    def customer_ids_for(main)
      scope = BackupPageConnection.where(account_id: @account.id)
      scope = scope.where(backup_page_id: main.id) if main
      scope.distinct.pluck(:contact_id)
    end

    def backup_counts_for(customer_ids, backup_ids)
      return {} if customer_ids.empty? || backup_ids.empty?

      BackupPageConnection.where(account_id: @account.id, contact_id: customer_ids, backup_page_id: backup_ids)
                          .group(:contact_id).count
    end

    def page_connection_counts(page_ids)
      return {} if page_ids.empty?

      BackupPageConnection.where(account_id: @account.id, backup_page_id: page_ids).group(:backup_page_id).count
    end

    def next_drip_estimate
      cadence = Backup::ConnectUpDrip.cadence_days(@account)
      last = @account.custom_attributes&.dig('backup_drip_last_run_at')
      return "every #{cadence} days (not yet run)" if last.blank?

      nxt = Time.zone.parse(last.to_s) + cadence.days
      nxt > Time.current ? nxt.iso8601 : 'due now'
    rescue StandardError
      "every #{cadence} days"
    end
  end
end
