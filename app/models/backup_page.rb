# frozen_string_literal: true

class BackupPage < ApplicationRecord
  STATUSES = %w[standby warming active banned retired].freeze
  PLATFORMS = %w[facebook instagram].freeze

  belongs_to :account

  validates :platform, presence: true, inclusion: { in: PLATFORMS }
  validates :page_id, presence: true
  validates :status, inclusion: { in: STATUSES }

  scope :ordered, -> { order(:position) }
  scope :healthy, -> { where.not(status: %w[banned retired]) }

  def promote!
    update!(status: 'active', health_check_at: Time.current)
  end

  def mark_banned!
    update!(status: 'banned')
  end
end
