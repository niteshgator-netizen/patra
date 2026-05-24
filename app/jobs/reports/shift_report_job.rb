# frozen_string_literal: true

module Reports
  class ShiftReportJob < ApplicationJob
    queue_as :scheduled_jobs

    def perform
      Account.find_each do |account|
        send_shift_report(account)
      end
    end

    private

    def send_shift_report(account)
      since = 8.hours.ago
      loads = account.game_actions.where(action_type: 'load', status: 'success').where('created_at > ?', since)
      cashouts = account.game_actions.where(action_type: 'cashout', status: 'success').where('created_at > ?', since)

      load_total = loads.sum(:amount)
      cashout_total = cashouts.sum(:amount)
      game_breakdown = loads.joins(agent_game: :game).group('games.slug').count
      top_player = loads.group(:contact_id).sum(:amount).max_by { |_, v| v }

      message = <<~MSG
        📊 Shift Report (#{since.strftime('%I%p')}-#{Time.current.strftime('%I%p')})
        Loads: $#{load_total} (#{loads.count} txns)
        Cashouts: $#{cashout_total} (#{cashouts.count} txns)
        Net: $#{load_total - cashout_total}
        Games: #{game_breakdown.map { |g, c| "#{g} #{c}" }.join(', ')}
      MSG

      Games::TelegramNotifier.notify(account, message) if defined?(Games::TelegramNotifier)
    end
  end
end
