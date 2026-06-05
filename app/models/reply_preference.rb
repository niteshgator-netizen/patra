# frozen_string_literal: true

class ReplyPreference < ApplicationRecord
  belongs_to :account

  validates :account_id, uniqueness: true
  validates :reply_tone, inclusion: { in: %w[casual professional minimal] }
  validates :max_reply_lines, numericality: { greater_than: 0, less_than_or_equal_to: 10 }
  validates :rag_example_count, numericality: { greater_than: 0, less_than_or_equal_to: 10 }

  # Class method to get-or-create for an account
  def self.for_account(account_id)
    find_or_create_by!(account_id: account_id)
  end
end
