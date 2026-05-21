class BellaRagUpload < ApplicationRecord
  belongs_to :account
  belongs_to :user

  STATUSES = %w[pending processing completed failed].freeze
  validates :status, inclusion: { in: STATUSES }
  validates :filename, presence: true

  scope :recent, -> { order(created_at: :desc) }
end
