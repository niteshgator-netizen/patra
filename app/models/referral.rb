# frozen_string_literal: true

class Referral < ApplicationRecord
  belongs_to :account
  belongs_to :referrer_contact, class_name: 'Contact'
  belongs_to :referred_contact, class_name: 'Contact', optional: true

  validates :status, inclusion: { in: %w[pending verified paid rejected] }
  validates :bonus_amount, numericality: { greater_than_or_equal_to: 0 }, allow_nil: true
  # Fraud guard: a player must not be able to refer themselves for a bonus.
  validate :no_self_referral

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

  private

  def no_self_referral
    return if referred_contact_id.blank?

    errors.add(:referred_contact_id, "can't match the referrer") if referred_contact_id == referrer_contact_id
  end
end
