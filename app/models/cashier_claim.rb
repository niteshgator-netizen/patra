# frozen_string_literal: true

class CashierClaim < ApplicationRecord
  STATUSES = %w[pending claimed completed expired].freeze
  ACTION_TYPES = %w[load cashout].freeze
  EXPIRY_MINUTES = 5

  belongs_to :account
  belongs_to :conversation
  belongs_to :contact
  belongs_to :claimed_by_user, class_name: 'User', optional: true

  validates :action_type, presence: true, inclusion: { in: ACTION_TYPES }
  validates :status, inclusion: { in: STATUSES }

  scope :pending, -> { where(status: 'pending') }
  scope :expired_due, -> { pending.where('expires_at <= ?', Time.current) }

  before_create :set_expiry

  def claim!(user)
    return false unless status == 'pending'

    update!(status: 'claimed', claimed_by_user: user, claimed_at: Time.current)
  end

  def complete!
    update!(status: 'completed', completed_at: Time.current)
  end

  def expire!
    update!(status: 'expired') if status == 'pending'
  end

  private

  def set_expiry
    self.expires_at ||= EXPIRY_MINUTES.minutes.from_now
  end
end
