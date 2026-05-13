class NotificationChannel < ApplicationRecord
  CHANNEL_TYPES = %w[telegram].freeze
  STATUSES = %w[active inactive failed].freeze
  DEFAULT_EVENT_FILTERS = {
    'load_success' => true,
    'load_failed' => true,
    'cashout_request' => true,
    'cashout_failed' => true,
    'human_escalation' => true,
    'api_error' => true
  }.freeze

  belongs_to :account

  encrypts :credentials

  validates :channel_type, inclusion: { in: CHANNEL_TYPES }
  validates :status, inclusion: { in: STATUSES }
  validates :account_id, uniqueness: { scope: :channel_type }

  scope :active, -> { where(status: 'active') }

  def telegram?
    channel_type == 'telegram'
  end

  def configured?
    return false unless telegram?

    creds = credentials || {}
    creds['bot_token'].to_s.present? && creds['chat_id'].to_s.present?
  end

  def should_notify?(event)
    return false unless status == 'active'

    filters = event_filters.presence || DEFAULT_EVENT_FILTERS
    filters[event.to_s] != false # default true if not explicitly false
  end

  def safe_credentials
    creds = credentials || {}
    {
      'bot_token' => creds['bot_token'].present? ? mask(creds['bot_token']) : nil,
      'chat_id' => creds['chat_id']
    }
  end

  def record_test!(success:, message:)
    update!(
      last_test_status: success ? 'success' : 'failed',
      last_test_message: message,
      last_test_at: Time.current
    )
  end

  def record_failure!
    increment!(:failure_count)
    update!(last_failure_at: Time.current)
  end

  def record_success!
    update!(last_used_at: Time.current)
    update!(failure_count: 0) if failure_count > 0
  end

  private

  def mask(str)
    return nil if str.blank?
    return '*' * str.length if str.length < 8

    "#{str[0..3]}...#{str[-4..]}"
  end
end
