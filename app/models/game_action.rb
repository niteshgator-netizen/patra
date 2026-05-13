class GameAction < ApplicationRecord
  ACTION_TYPES = %w[load cashout add_player balance_check player_balance_check].freeze
  STATUSES = %w[pending success failed].freeze

  belongs_to :account
  belongs_to :agent_game
  belongs_to :contact, optional: true
  belongs_to :conversation, optional: true

  validates :action_type, inclusion: { in: ACTION_TYPES }
  validates :status, inclusion: { in: STATUSES }
  validates :order_id, presence: true, uniqueness: { scope: :account_id }

  scope :successful, -> { where(status: 'success') }
  scope :failed, -> { where(status: 'failed') }
  scope :for_player, ->(username) { where(game_username: username) }
  scope :recent, -> { order(created_at: :desc) }

  def succeeded?
    status == 'success'
  end

  def failed?
    status == 'failed'
  end

  def self.generate_order_id(prefix: 'pat')
    "#{prefix}_#{SecureRandom.hex(8)}_#{Time.now.to_i}"
  end

  # Returns the total amount this contact has loaded today (UTC)
  def self.loaded_today_for_contact(account_id:, contact_id:)
    where(account_id: account_id, contact_id: contact_id, action_type: 'load', status: 'success')
      .where('created_at >= ?', Time.now.utc.beginning_of_day)
      .sum(:amount)
  end
end
