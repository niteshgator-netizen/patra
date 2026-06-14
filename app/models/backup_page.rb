# frozen_string_literal: true

class BackupPage < ApplicationRecord
  STATUSES = %w[standby warming active banned retired].freeze
  PLATFORMS = %w[facebook instagram].freeze
  ROLES = %w[main backup].freeze

  belongs_to :account
  has_many :backup_page_connections, dependent: :destroy_async

  validates :platform, presence: true, inclusion: { in: PLATFORMS }
  validates :page_id, presence: true
  validates :status, inclusion: { in: STATUSES }
  validates :role, inclusion: { in: ROLES }

  scope :ordered, -> { order(:position) }
  scope :healthy, -> { where.not(status: %w[banned retired]) }
  # Coverage model (B-PAGES): "live" = usable for coverage (not banned/retired). A banned page drops
  # out of these scopes so coverage recomputes with NO migration / failover.
  scope :live, -> { where.not(status: %w[banned retired]) }
  scope :main_pages, -> { where(role: 'main') }
  scope :backups, -> { where(role: 'backup') }
  scope :live_backups, -> { backups.live }

  # Page access tokens never leave the server — stripped from every JSON render.
  def as_json(options = {})
    opts = (options || {}).dup
    opts[:except] = Array(opts[:except]) | [:access_token]
    super(opts)
  end

  def promote!
    update!(status: 'active', health_check_at: Time.current)
  end

  def mark_banned!
    update!(status: 'banned')
  end

  def live?
    !%w[banned retired].include?(status)
  end

  def main?
    role == 'main'
  end

  # Customer-facing deep link to start a Messenger thread with this page (used by the connect-up invite).
  def m_me_link
    "https://m.me/#{page_id}"
  end
end
