# frozen_string_literal: true

class FeatureFlag < ApplicationRecord
  validates :name, presence: true, uniqueness: true
  validates :percentage_rollout, numericality: { only_integer: true, in: 0..100 }

  def self.enabled?(name, account = nil)
    flag = find_by(name: name.to_s)
    return false unless flag

    return true if flag.enabled_globally
    return true if account && flag.enabled_for_accounts.include?(account.id)

    return false if account.blank? || flag.percentage_rollout.zero?

    (account.id % 100) < flag.percentage_rollout
  end
end
