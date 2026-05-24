# frozen_string_literal: true

module Reports
  class DailySummaryJob < ApplicationJob
    queue_as :scheduled_jobs

    def perform
      period = 1.day.ago.all_day

      Account.find_each do |account|
        send_summary(account, period)
      end
    end

    private

    def send_summary(account, period)
      stats = build_stats(account, period)
      text = format_message(account, stats, period)
      Games::TelegramNotifier.test_message(account: account, custom_text: text)
    rescue StandardError => e
      Rails.logger.error("[Reports::DailySummaryJob] account=#{account.id} #{e.class}: #{e.message}")
    end

    def build_stats(account, period)
      messages = Message.unscoped.where(account_id: account.id, private: false)
      loads = account.game_actions.where(action_type: 'load', status: 'success', created_at: period)
      cashouts = account.game_actions.where(action_type: 'cashout', status: 'success', created_at: period)
      load_amount = loads.sum(:amount).to_f
      cashout_amount = cashouts.sum(:amount).to_f
      ai_rate = Analytics::AiHandleRateService.new(account, period: period).call[:rate]

      {
        conversations: account.conversations.where(created_at: period).count,
        messages_in: messages.incoming.where(created_at: period).count,
        messages_out: messages.outgoing.where(created_at: period).count,
        ai_handle_rate: ai_rate,
        loads_amount: load_amount.round(2),
        loads_count: loads.count,
        cashouts_amount: cashout_amount.round(2),
        cashouts_count: cashouts.count,
        net: (load_amount - cashout_amount).round(2)
      }
    end

    def format_message(account, stats, period)
      I18n.t(
        'patra.reports.daily_summary',
        account: account.name,
        date: period.begin.to_date,
        conversations: stats[:conversations],
        messages_in: stats[:messages_in],
        messages_out: stats[:messages_out],
        ai_handle_rate: stats[:ai_handle_rate],
        loads_amount: format('%.2f', stats[:loads_amount]),
        loads_count: stats[:loads_count],
        cashouts_amount: format('%.2f', stats[:cashouts_amount]),
        cashouts_count: stats[:cashouts_count],
        net: format('%.2f', stats[:net])
      )
    end
  end
end
