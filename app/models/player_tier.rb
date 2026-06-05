# frozen_string_literal: true

class PlayerTier < ApplicationRecord
  belongs_to :account
  has_many :contacts, dependent: :nullify

  validates :name, presence: true, uniqueness: { scope: :account_id }
  validates :name, inclusion: { in: %w[regular vip selected new_player blocked] }

  scope :ordered, -> { order(sort_order: :asc) }

  # Get override value for a specific rule field, or nil if not overridden
  def override_for(field_name)
    rule_overrides&.dig(field_name.to_s)
  end

  # Check if this tier blocks all actions
  def blocked?
    name == 'blocked'
  end

  # Badge display
  def badge
    badge_text || name.titleize
  end
end
