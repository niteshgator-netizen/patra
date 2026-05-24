# frozen_string_literal: true

class ApprovalRequest < ApplicationRecord
  STATUSES = %w[pending approved rejected].freeze

  belongs_to :account
  belongs_to :requesting_user, class_name: 'User'
  belongs_to :approving_user, class_name: 'User', optional: true

  validates :action_type, presence: true
  validates :status, inclusion: { in: STATUSES }

  scope :pending, -> { where(status: 'pending') }

  def approve!(user)
    update!(status: 'approved', approving_user: user, responded_at: Time.current)
  end

  def reject!(user)
    update!(status: 'rejected', approving_user: user, responded_at: Time.current)
  end
end
