# frozen_string_literal: true

module ContactProfileStats
  extend ActiveSupport::Concern

  FINANCE_LOG_KEY = 'patra_finance_logs'

  def conversation_loyalty_tier
    conv_count = conversations.count
    days_active = created_at ? ((Time.current - created_at) / 1.day).to_i : 0

    if conv_count >= 20 && days_active >= 60
      'vip'
    elsif conv_count >= 5 && days_active >= 14
      'regular'
    else
      'new'
    end
  end

  def profile_loyalty_tier
    custom_attributes['loyalty_tier'].presence || conversation_loyalty_tier
  end

  def deposit_stats
    logs = finance_log_entries.select { |e| e['kind'] == 'deposit' }
    count = logs.size.positive? ? logs.size : custom_attributes['deposit_count'].to_i
    total = if logs.any?
              logs.sum { |e| e['amount'].to_f }
            else
              custom_attributes['total_deposits'].to_f
            end
    { count: count, total: total.round(2) }
  end

  def cashout_stats
    logs = finance_log_entries.select { |e| e['kind'] == 'cashout' }
    count = logs.size
    total = if logs.any?
              logs.sum { |e| e['amount'].to_f }
            else
              custom_attributes['total_cashouts'].to_f
            end
    { count: count, total: total.round(2) }
  end

  def preferred_payment_display
    custom_attributes['preferred_payment_method'].presence || computed_preferred_payment
  end

  def last_game_played
    custom_attributes['preferred_platform'].presence || custom_attributes['game_username'].presence
  end

  def profile_stats
    {
      loyalty_tier: profile_loyalty_tier,
      conversation_count: conversations.count,
      deposits: deposit_stats,
      cashouts: cashout_stats,
      preferred_payment: preferred_payment_display,
      last_game: last_game_played
    }
  end

  private

  def finance_log_entries
    Array(custom_attributes[FINANCE_LOG_KEY]).filter_map do |raw|
      raw.is_a?(Hash) ? raw.stringify_keys : nil
    end
  end

  def computed_preferred_payment
    finance_log_entries
      .select { |e| e['kind'] == 'deposit' && e['platform'].present? }
      .group_by { |e| e['platform'] }
      .max_by { |_, entries| entries.size }
      &.first || 'Unknown'
  end
end
