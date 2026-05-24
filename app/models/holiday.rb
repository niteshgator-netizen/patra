# frozen_string_literal: true

class Holiday < ApplicationRecord
  belongs_to :account
  belongs_to :inbox, optional: true

  validates :closed_on, presence: true

  scope :for_date, ->(date) { where(closed_on: date) }
  scope :for_account, ->(account_id) { where(account_id: account_id) }
end
