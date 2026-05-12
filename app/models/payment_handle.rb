# frozen_string_literal: true

class PaymentHandle < ApplicationRecord
  belongs_to :account

  encrypts :verification_email_password

  PLATFORMS = %w[cashapp chime paypal venmo zelle].freeze
  MAX_HANDLES_PER_PLATFORM = {
    'cashapp' => 3,
    'chime' => 3,
    'paypal' => 3,
    'venmo' => 2
  }.freeze
  STATUSES = %w[active failed disabled].freeze

  scope :active_for, ->(platform) { where(platform: platform, status: 'active').order(:priority) }
  scope :for_platform, ->(platform) { where(platform: platform).order(:priority) }

  validates :platform, presence: true, inclusion: { in: PLATFORMS }
  validates :handle, presence: true
  validates :priority, presence: true, numericality: { only_integer: true, greater_than: 0 }
  validates :status, inclusion: { in: STATUSES }
  validate :cannot_exceed_max_handles

  before_validation :normalize_handle_value

  def normalized_handle
    handle.to_s.gsub(/^[\$@]/, '').strip.downcase
  end

  def display_handle
    display_name.presence || handle
  end

  def active?
    status == 'active'
  end

  def in_cooldown?
    cooldown_until.present? && cooldown_until > Time.current
  end

  def available?
    active? && !in_cooldown?
  end

  private

  def normalize_handle_value
    self.handle = normalized_handle if handle.present?
  end

  def cannot_exceed_max_handles
    return if account.blank? || platform.blank?

    max = MAX_HANDLES_PER_PLATFORM[platform] || 1
    scope = account.payment_handles.where(platform: platform)
    scope = scope.where.not(id: id) if persisted?
    return if scope.count < max

    errors.add(:base, "cannot exceed #{max} handles for this platform")
  end
end
