# frozen_string_literal: true

class PaymentHandle < ApplicationRecord
  belongs_to :account

  encrypts :verification_email_password

  PLATFORMS = %w[cashapp chime venmo paypal varo zelle boltpay applepay usdt].freeze
  STATUSES = %w[active limited frozen cooldown disabled].freeze
  MAX_PRIORITY = {
    'cashapp' => 3, 'chime' => 3, 'paypal' => 3,
    'venmo' => 2,
    'varo' => 1, 'zelle' => 1, 'boltpay' => 1, 'applepay' => 1, 'usdt' => 1
  }.freeze

  validates :platform, presence: true, inclusion: { in: PLATFORMS }
  validates :handle, presence: true
  validates :priority, presence: true, numericality: { only_integer: true, greater_than: 0 }
  validates :status, inclusion: { in: STATUSES }
  validate :priority_within_max

  scope :active_for, lambda { |platform|
    where(platform: platform, status: 'active')
      .where('cooldown_until IS NULL OR cooldown_until < ?', Time.current)
      .order(:priority)
  }

  def usable?
    status == 'active' && (cooldown_until.nil? || cooldown_until < Time.current)
  end

  def display_handle
    return handle if handle.start_with?('$', '@')

    case platform
    when 'cashapp' then "$#{handle}"
    else "@#{handle}"
    end
  end

  def normalized_handle
    handle.to_s.gsub(/^[\$@]/, '').strip.downcase
  end

  private

  def priority_within_max
    max = MAX_PRIORITY[platform]
    return unless max && priority && priority > max

    errors.add(:priority, "exceeds max for #{platform} (#{max})")
  end
end
