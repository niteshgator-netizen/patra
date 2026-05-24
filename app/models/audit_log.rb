# frozen_string_literal: true

class AuditLog < ApplicationRecord
  self.record_timestamps = false

  belongs_to :account
  belongs_to :user, optional: true

  validates :action, presence: true

  before_create { self.created_at ||= Time.current }

  def readonly?
    persisted?
  end

  before_destroy { throw(:abort) }
end
