# frozen_string_literal: true

# Daily win-back sweep. Scheduled via config/schedule.yml (sidekiq-cron).
module Games
  class WinbackJob
    include Sidekiq::Worker
    sidekiq_options queue: :scheduled_jobs, retry: 1

    def perform
      Games::WinbackService.run_all
    end
  end
end
