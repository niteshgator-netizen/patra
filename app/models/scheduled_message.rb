# frozen_string_literal: true

class ScheduledMessage < ApplicationRecord
  STATUSES = %w[pending sent cancelled].freeze

  belongs_to :account
  belongs_to :conversation
  belongs_to :created_by_user, class_name: 'User'

  validates :content, presence: true
  validates :scheduled_at, presence: true
  validates :status, inclusion: { in: STATUSES }

  scope :due, -> { where(status: 'pending').where('scheduled_at <= ?', Time.current) }
end
