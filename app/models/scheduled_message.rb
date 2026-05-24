# frozen_string_literal: true

class ScheduledMessage < ApplicationRecord
  STATUSES = %w[pending sent cancelled].freeze
  RECURRENCES = %w[daily weekly monthly].freeze

  belongs_to :account
  belongs_to :conversation
  belongs_to :created_by_user, class_name: 'User'

  validates :content, presence: true
  validates :scheduled_at, presence: true
  validates :status, inclusion: { in: STATUSES }
  validates :recurrence, inclusion: { in: RECURRENCES }, allow_nil: true

  scope :due, -> { where(status: 'pending').where('scheduled_at <= ?', Time.current) }

  def recurring?
    recurrence.present?
  end

  def next_occurrence
    return nil unless recurring?

    base = scheduled_at || Time.current
    case recurrence
    when 'daily' then base + 1.day
    when 'weekly' then base + 1.week
    when 'monthly' then base + 1.month
    end
  end
end
