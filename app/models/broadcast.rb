# frozen_string_literal: true

class Broadcast < ApplicationRecord
  STATUSES = %w[draft scheduled sending sent cancelled].freeze
  CHANNELS = %w[facebook sms email whatsapp instagram].freeze

  belongs_to :account
  belongs_to :created_by_user, class_name: 'User', optional: true

  validates :name, :content, :channel, presence: true
  validates :channel, inclusion: { in: CHANNELS }
  validates :status, inclusion: { in: STATUSES }

  scope :due, -> { where(status: 'scheduled').where('scheduled_at <= ?', Time.current) }
  scope :draft_or_scheduled, -> { where(status: %w[draft scheduled]) }
end
