# frozen_string_literal: true

class PaymentHandle < ApplicationRecord
  belongs_to :account

  encrypts :verification_email_password

  PLATFORMS = %w[cashapp chime paypal venmo zelle bitcoin ethereum usdt].freeze
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
    h = handle.to_s.strip
    return h if h.start_with?('$', '@')
    return '' if h.blank?

    case platform.to_s.downcase
    when 'cashapp', 'chime' then "$#{h}"
    when 'venmo'            then "@#{h}"
    else h
    end
  end

  def display_person_name
    name = try(:display_name).to_s.strip
    name.presence
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
