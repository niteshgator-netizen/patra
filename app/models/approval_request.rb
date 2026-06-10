# frozen_string_literal: true

class ApprovalRequest < ApplicationRecord
  STATUSES = %w[pending approved rejected].freeze

  belongs_to :account
  belongs_to :requesting_user, class_name: 'User'
  belongs_to :approving_user, class_name: 'User', optional: true

  validates :action_type, presence: true
  validates :status, inclusion: { in: STATUSES }

  scope :pending, -> { where(status: 'pending') }

  # F15 — auto-resume (SHIPPED DARK): when PATRA_APPROVAL_AUTORESUME=true,
  # an approval transition enqueues the original cashout for execution.
  # Flag off (default) = callback no-ops = today's manual behavior.
  after_update_commit :enqueue_auto_resume, if: -> { saved_change_to_status? && status == 'approved' }

  def approve!(user)
    update!(status: 'approved', approving_user: user, responded_at: Time.current)
  end

  def reject!(user)
    update!(status: 'rejected', approving_user: user, responded_at: Time.current)
  end

  private

  def enqueue_auto_resume
    return unless defined?(Approvals::AutoResume) && Approvals::AutoResume.enabled?

    Approvals::AutoResumeJob.perform_later(id)
  rescue StandardError => e
    Rails.logger.error("[ApprovalRequest] auto-resume enqueue failed id=#{id}: #{e.class}: #{e.message}")
  end
end
