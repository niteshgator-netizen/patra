# frozen_string_literal: true

class AutomationFlowRun < ApplicationRecord
  STATUSES = %w[running completed failed paused].freeze

  belongs_to :automation_flow
  belongs_to :conversation, optional: true
  belongs_to :contact, optional: true

  validates :status, inclusion: { in: STATUSES }
  validates :started_at, presence: true

  scope :running, -> { where(status: 'running') }
  scope :preview, -> { where(preview_mode: true) }

  def append_log!(entry)
    self.step_log = (step_log || []) + [entry.merge('at' => Time.current.iso8601)]
    save!
  end

  def complete!(status: 'completed')
    update!(status: status, completed_at: Time.current)
    automation_flow.increment_stat!(status == 'completed' ? 'completions' : 'failures')
  end
end
