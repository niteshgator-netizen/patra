# frozen_string_literal: true

# A Patra subscription plan DEFINITION (name, price, limits, feature defaults).
# Definition only for now — nothing enforces these limits yet; enforcement
# ships later. Accounts point at a plan via accounts.patra_plan_id (no FK,
# nullable, so deleting a plan can never strand an account).
#
# == Schema Information
#
# Table name: patra_plans
#
#  id                       :bigint           not null, primary key
#  active                   :boolean          default(TRUE), not null
#  agents_limit             :integer
#  ai_replies_monthly_limit :integer
#  currency                 :string           default("USD"), not null
#  features                 :jsonb            not null
#  inboxes_limit            :integer
#  name                     :string           not null
#  period                   :string           default("monthly"), not null
#  position                 :integer          default(0), not null
#  price                    :decimal(12, 2)
#
class PatraPlan < ApplicationRecord
  CURRENCIES = %w[USD EUR GBP CAD AUD].freeze
  PERIODS = %w[monthly yearly].freeze

  validates :name, presence: true, uniqueness: true, length: { maximum: 80 }
  validates :currency, inclusion: { in: CURRENCIES }
  validates :period, inclusion: { in: PERIODS }
  validates :price, numericality: { greater_than_or_equal_to: 0 }, allow_nil: true
  validates :agents_limit, :inboxes_limit, :ai_replies_monthly_limit,
            numericality: { only_integer: true, greater_than_or_equal_to: 0 }, allow_nil: true

  scope :ordered, -> { order(:position, :id) }

  def accounts
    Account.where(patra_plan_id: id)
  end

  def feature_enabled?(feature_name)
    features[feature_name.to_s] == true
  end

  def display_price
    return 'Not set' if price.blank?

    "#{currency} #{format('%.2f', price)} / #{period == 'yearly' ? 'yr' : 'mo'}"
  end
end
