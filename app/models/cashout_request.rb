class CashoutRequest < ApplicationRecord
  STATUSES = %w[pending approved paid rejected].freeze

  belongs_to :account
  belongs_to :agent_game
  belongs_to :contact
  belongs_to :conversation, optional: true
  belongs_to :withdraw_action, class_name: 'GameAction', optional: true
  belongs_to :reload_action, class_name: 'GameAction', optional: true

  validates :status, inclusion: { in: STATUSES }
  validates :game_username, presence: true
  validates :cashout_amount, numericality: { greater_than: 0 }

  scope :pending, -> { where(status: 'pending') }
  scope :recent, -> { order(created_at: :desc) }
end
