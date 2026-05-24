# frozen_string_literal: true

class PlayerBonus < ApplicationRecord
  self.record_timestamps = false

  belongs_to :account
  belongs_to :contact
  belongs_to :given_by_user, class_name: 'User'

  validates :amount, presence: true, numericality: { greater_than: 0 }

  before_create { self.created_at ||= Time.current }
end
