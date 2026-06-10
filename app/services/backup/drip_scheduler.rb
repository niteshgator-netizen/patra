# frozen_string_literal: true

module Backup
  class DripScheduler
    # days-in-warming => phase. Phase is the HIGHEST key <= days, so day 2 stays
    # 'responding' and day 8 stays 'fully_active' (the old exact-match lookup sent
    # any unlisted day straight to fully_active).
    WARMING_SCHEDULE = { 1 => 'responding', 3 => 'partial_intro', 7 => 'fully_active' }.freeze
    # First 24h after entering warming — page stays quiet.
    PRE_WARM_PHASE = 'pre_warm'
    PROMOTE_AFTER_DAYS = 7

    def initialize(backup_page:)
      @page = backup_page
    end

    # Called hourly (Backup::HealthCheckJob) for pages already in 'warming'.
    # The warming clock runs from stats['warming_started_at'] — NOT updated_at,
    # which the hourly health check touches via update!(health_check_at:).
    # Returns the resolved phase string.
    def advance_warming
      ensure_warming_stamp!
      days = days_in_warming
      phase = phase_for(days)

      @page.promote! if phase == 'fully_active' && days >= PROMOTE_AFTER_DAYS && health_ok?
      phase
    end

    private

    # Stamped on the first advance_warming after the page enters 'warming'
    # (the hourly sweep makes this accurate to within an hour of the flip).
    # Never overwrites an existing stamp.
    def ensure_warming_stamp!
      stats = @page.stats || {}
      return if stats['warming_started_at'].present?

      @page.update!(stats: stats.merge('warming_started_at' => Time.current.iso8601))
    end

    def days_in_warming
      raw = (@page.stats || {})['warming_started_at']
      return 0 if raw.blank?

      started = Time.zone.parse(raw.to_s)
      return 0 if started.nil?

      ((Time.current - started) / 1.day).to_i
    rescue ArgumentError
      0
    end

    def phase_for(days)
      reached = WARMING_SCHEDULE.keys.select { |threshold| days >= threshold }
      return PRE_WARM_PHASE if reached.empty?

      WARMING_SCHEDULE[reached.max]
    end

    def health_ok?
      @page.health_check_at.present? && @page.health_check_at > 1.hour.ago
    end
  end
end
