# frozen_string_literal: true

class AgentShift < ApplicationRecord
  belongs_to :account
  belongs_to :user

  validates :day_of_week, presence: true, inclusion: { in: 0..6 }
  validates :start_time, :end_time, presence: true

  scope :active, -> { where(active: true) }
  scope :for_day, ->(day) { active.where(day_of_week: day) }

  def self.agent_on_shift?(account:, user:)
    now = Time.current.in_time_zone(account.timezone || 'UTC')
    current_time = now.strftime('%H:%M:%S')
    for_day(now.wday).where(account: account, user: user).any? do |shift|
      shift.start_time.strftime('%H:%M:%S') <= current_time &&
        shift.end_time.strftime('%H:%M:%S') >= current_time
    end
  end
end
