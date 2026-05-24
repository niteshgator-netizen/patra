# frozen_string_literal: true

class DripCampaign < ApplicationRecord
  STATUSES = %w[draft active paused completed].freeze

  belongs_to :account
  belongs_to :automation_flow

  validates :status, inclusion: { in: STATUSES }

  scope :active, -> { where(status: 'active') }
  scope :due, -> { active.where('scheduled_at IS NULL OR scheduled_at <= ?', Time.current) }
end
