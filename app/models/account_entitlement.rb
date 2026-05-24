# frozen_string_literal: true

class AccountEntitlement < ApplicationRecord
  PLANS = %w[free starter pro business enterprise].freeze

  DEFAULT_LIMITS = {
    'free' => { max_contacts: 500, max_agents: 2, max_inboxes: 2, max_ai_replies_per_month: 100, max_broadcasts_per_month: 5 },
    'starter' => { max_contacts: 2000, max_agents: 5, max_inboxes: 5, max_ai_replies_per_month: 500, max_broadcasts_per_month: 20 },
    'pro' => { max_contacts: 10_000, max_agents: 15, max_inboxes: 15, max_ai_replies_per_month: 2000, max_broadcasts_per_month: 100 },
    'business' => { max_contacts: 50_000, max_agents: 50, max_inboxes: 50, max_ai_replies_per_month: 10_000, max_broadcasts_per_month: 500 },
    'enterprise' => { max_contacts: nil, max_agents: nil, max_inboxes: nil, max_ai_replies_per_month: nil, max_broadcasts_per_month: nil }
  }.freeze

  belongs_to :account

  validates :plan_slug, presence: true, inclusion: { in: PLANS }

  after_initialize :set_default_limits, if: :new_record?

  def self.allowed?(account, feature)
    entitlement = find_by(account: account)
    return true unless entitlement

    limits = entitlement.limits.symbolize_keys
    case feature.to_sym
    when :broadcast
      check_limit(account, limits[:max_broadcasts_per_month], :broadcasts)
    when :ai_reply
      check_limit(account, limits[:max_ai_replies_per_month], :ai_replies)
    when :contact
      check_limit(account, limits[:max_contacts], :contacts, count: true)
    when :agent
      check_limit(account, limits[:max_agents], :agents, count: true)
    when :inbox
      check_limit(account, limits[:max_inboxes], :inboxes, count: true)
    else
      true
    end
  end

  def self.check_limit(account, max, metric, count: false)
    return true if max.nil?

    current = if count
                account.send(metric).count
              else
                UsageRecord.find_by(account: account, metric: metric, period_start: Time.current.beginning_of_month)&.quantity || 0
              end
    current < max
  end

  private

  def set_default_limits
    self.limits = DEFAULT_LIMITS[plan_slug] || DEFAULT_LIMITS['free'] if limits.blank?
  end
end
