# frozen_string_literal: true

module Backup
  class HealthCheckJob < ApplicationJob
    queue_as :scheduled_jobs
    retry_on StandardError, wait: :polynomially_longer, attempts: 3

    BAN_ERROR_CODES = [190, 368].freeze

    def perform
      BackupPage.find_each do |page|
        check_page(page)
      rescue StandardError => e
        Rails.logger.error("[Backup::HealthCheckJob] page #{page.id} check failed: #{e.class}: #{e.message}")
      end
    end

    private

    def check_page(page)
      healthy = can_send?(page)
      page.update!(health_check_at: Time.current)

      if healthy
        Backup::DripScheduler.new(backup_page: page).advance_warming if page.status == 'warming'
      else
        handle_unhealthy(page)
      end
    end

    def can_send?(page)
      return false if page.access_token.blank?

      response = HTTParty.get(
        "https://graph.facebook.com/v19.0/#{page.page_id}",
        query: { access_token: page.access_token, fields: 'id,name' }
      )
      return false if BAN_ERROR_CODES.include?(response.dig('error', 'code'))

      response.success?
    rescue StandardError
      false
    end

    def handle_unhealthy(page)
      if page.status == 'active'
        promote_next_backup(page)
      else
        page.mark_banned!
        notify_ban(page)
      end
    end

    def promote_next_backup(page)
      next_page = page.account.backup_pages.healthy.where('position > ?', page.position).ordered.first
      return unless next_page

      page.mark_banned!
      next_page.promote!
      Backup::CustomerMigration.migrate(page.account, from: page, to: next_page)
      notify_switch(page, next_page)
    end

    def notify_ban(page)
      Games::TelegramNotifier.api_error(account: page.account,
                                        message: "Backup page #{page.page_name} banned - status updated",
                                        details: "page_id=#{page.page_id}")
    rescue StandardError => e
      Rails.logger.error("[Backup::HealthCheckJob] notify_ban failed: #{e.class}: #{e.message}")
    end

    def notify_switch(old_page, new_page)
      Games::TelegramNotifier.api_error(account: old_page.account,
                                        message: "Primary FB page banned - auto-switched to #{new_page.page_name}",
                                        details: "from=#{old_page.page_id} to=#{new_page.page_id}")
    rescue StandardError => e
      Rails.logger.error("[Backup::HealthCheckJob] notify_switch failed: #{e.class}: #{e.message}")
    end
  end
end
