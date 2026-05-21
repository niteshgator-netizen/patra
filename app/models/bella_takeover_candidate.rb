class BellaTakeoverCandidate < ApplicationRecord
  belongs_to :account
  belongs_to :conversation
  belongs_to :message

  STATUSES = %w[queued auto_added approved rejected].freeze
  AUTO_ADD_THRESHOLD = 0.7

  validates :status, inclusion: { in: STATUSES }
  validates :confidence_score, numericality: { in: 0.0..1.0 }

  scope :queued, -> { where(status: 'queued') }
  scope :auto_added, -> { where(status: 'auto_added') }
  scope :reviewable, -> { where(status: 'queued') }
end
