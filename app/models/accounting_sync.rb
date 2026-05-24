# frozen_string_literal: true

class AccountingSync < ApplicationRecord
  PROVIDERS = %w[quickbooks xero].freeze
  STATUSES = %w[pending configured syncing error].freeze

  belongs_to :account

  validates :provider, presence: true, inclusion: { in: PROVIDERS }
  validates :status, inclusion: { in: STATUSES }
end
