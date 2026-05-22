class FacebookIdentity < ApplicationRecord
  encrypts :user_access_token

  belongs_to :account
  has_many :channel_apis, class_name: '::Channel::Api', foreign_key: :facebook_identity_id, dependent: :nullify

  STATUSES = %w[active token_expired revoked].freeze
  validates :status, inclusion: { in: STATUSES }
  validates :fb_user_id, presence: true, uniqueness: { scope: :account_id }
  validates :user_access_token, presence: true

  scope :active, -> { where(status: 'active') }

  def inboxes
    Inbox.where(channel_type: 'Channel::Api', channel_id: channel_apis.select(:id))
  end

  def page_count
    inboxes.count
  end

  def token_expiring_soon?(within: 7.days)
    return false unless token_expires_at

    token_expires_at < (Time.current + within)
  end

  def mark_token_expired!
    update!(status: 'token_expired')
  end

  def mark_revoked!
    update!(status: 'revoked')
  end

  def mark_refreshed!(new_token:, new_expiry:)
    update!(
      user_access_token: new_token,
      token_expires_at: new_expiry,
      token_last_refreshed_at: Time.current,
      status: 'active'
    )
  end
end
