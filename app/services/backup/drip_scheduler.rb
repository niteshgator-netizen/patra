# frozen_string_literal: true

module Backup
  class DripScheduler
    WARMING_SCHEDULE = { 1 => 'responding', 3 => 'partial_intro', 7 => 'fully_active' }.freeze

    def initialize(backup_page:)
      @page = backup_page
    end

    def advance_warming
      days = days_in_warming
      phase = WARMING_SCHEDULE[days] || WARMING_SCHEDULE.values.last

      case phase
      when 'responding'
        @page.update!(status: 'warming')
      when 'fully_active'
        @page.promote! if health_ok?
      end
    end

    private

    def days_in_warming
      return 0 unless @page.updated_at

      ((Time.current - @page.updated_at) / 1.day).to_i + 1
    end

    def health_ok?
      @page.health_check_at.present? && @page.health_check_at > 1.hour.ago
    end
  end
end
