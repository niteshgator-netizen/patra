# frozen_string_literal: true

module ContactProfileStats
  extend ActiveSupport::Concern

  FINANCE_LOG_KEY = 'patra_finance_logs'

  # Defensive guard: a negative finance-log 'amount' must never persist again (a
  # garbage value once appeared on reprocessed Chime entries). Registered here so it
  # runs on EVERY contact save — catching all write paths (ghost_payment_store, IMAP
  # jobs, image extractor, manual), since they all eventually call contact.save!.
  included do
    before_save :sanitize_finance_log_amounts
  end

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

  # before_save guard (registered in `included do` above). Normalizes any negative
  # finance-log 'amount' to the verified email_amount (when positive), else its
  # absolute value. Null-safe, idempotent, cheap (early-returns when no logs / no
  # negatives), and NEVER raises — a hiccup here must never block a contact save.
  def sanitize_finance_log_amounts
    attrs = custom_attributes
    return unless attrs.is_a?(Hash)

    logs = attrs[FINANCE_LOG_KEY] || attrs[FINANCE_LOG_KEY.to_sym]
    return unless logs.is_a?(Array)

    changed = false
    logs.each do |entry|
      next unless entry.is_a?(Hash)

      has_string_key = entry.key?('amount')
      amt = has_string_key ? entry['amount'] : entry[:amount]
      next unless amt.is_a?(Numeric) && amt.negative?

      # Prefer the verified email_amount (the truth); else fall back to abs.
      email_amt = entry['email_amount'] || entry[:email_amount]
      corrected = (email_amt.is_a?(Numeric) && email_amt.positive?) ? email_amt : amt.abs

      if has_string_key
        entry['amount'] = corrected
      else
        entry[:amount] = corrected
      end
      changed = true
    end

    # Only reassign (and dirty the column) when we actually fixed something.
    self.custom_attributes = attrs if changed
  rescue StandardError => e
    Rails.logger.warn("[ContactProfileStats] sanitize_finance_log_amounts skipped: #{e.class}: #{e.message}")
    nil
  end

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
