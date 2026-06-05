# frozen_string_literal: true

class Referral < ApplicationRecord
  belongs_to :account
  belongs_to :referrer_contact, class_name: 'Contact'
  belongs_to :referred_contact, class_name: 'Contact', optional: true

  validates :status, inclusion: { in: %w[pending verified paid rejected] }

  scope :pending, -> { where(status: 'pending') }
  scope :verified, -> { where(status: 'verified') }
  scope :paid, -> { where(status: 'paid') }

  def mark_verified!
    update!(status: 'verified')
  end

  def mark_paid!(amount:, type:)
    update!(status: 'paid', bonus_amount: amount, bonus_type: type, paid_at: Time.current)
  end

  def mark_rejected!
    update!(status: 'rejected')
  end
end
