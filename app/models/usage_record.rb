# frozen_string_literal: true

class UsageRecord < ApplicationRecord
  METRICS = %w[messages_sent ai_replies contacts conversations broadcasts api_calls].freeze

  belongs_to :account

  validates :metric, presence: true, inclusion: { in: METRICS }
  validates :quantity, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validates :period_start, :period_end, presence: true

  def self.increment!(account:, metric:, quantity: 1)
    period_start = Time.current.beginning_of_month
    period_end = Time.current.end_of_month
    record = find_or_initialize_by(account: account, metric: metric, period_start: period_start)
    record.period_end = period_end
    record.quantity = (record.quantity || 0) + quantity
    record.save!
  end
end
