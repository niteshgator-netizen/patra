# frozen_string_literal: true

class ReplyPreference < ApplicationRecord
  belongs_to :account

  validates :account_id, uniqueness: true
  validates :reply_tone, inclusion: { in: %w[casual professional minimal] }
  # Money-flow forks read these — an unknown value silently changes transfer behavior.
  validates :transfer_mode, inclusion: { in: %w[whole deposit_only] }, allow_nil: true
  validates :transfer_deposit_shortfall_mode, inclusion: { in: %w[transfer_available refuse] }, allow_nil: true
  validates :max_reply_lines, numericality: { greater_than: 0, less_than_or_equal_to: 10 }
  validates :rag_example_count, numericality: { greater_than: 0, less_than_or_equal_to: 10 }

  # Class method to get-or-create for an account
  def self.for_account(account_id)
    find_or_create_by!(account_id: account_id)
  end
end
