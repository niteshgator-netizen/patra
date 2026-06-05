# frozen_string_literal: true

class GameRule < ApplicationRecord
  belongs_to :account
  belongs_to :game

  validates :account_id, uniqueness: { scope: :game_id }

  # Parse JSON tier arrays
  def freeplay_tier_list
    JSON.parse(freeplay_eligible_tiers || '["new_player"]')
  rescue JSON::ParserError
    ['new_player']
  end

  def deposit_bonus_tier_list
    JSON.parse(deposit_bonus_eligible_tiers || '["all"]')
  rescue JSON::ParserError
    ['all']
  end

  # Check if a contact's tier qualifies for freeplay
  def freeplay_eligible?(contact)
    return false unless freeplay_enabled

    tier_name = contact.player_tier&.name || 'regular'
    tiers = freeplay_tier_list
    tiers.include?('all') || tiers.include?(tier_name)
  end

  # Check if a contact's tier qualifies for deposit bonus
  def deposit_bonus_eligible?(contact)
    return false unless deposit_bonus_enabled

    tier_name = contact.player_tier&.name || 'regular'
    tiers = deposit_bonus_tier_list
    tiers.include?('all') || tiers.include?(tier_name)
  end

  # Calculate deposit bonus amount
  def calculate_bonus(deposit_amount)
    return 0 unless deposit_bonus_enabled
    return 0 if deposit_amount < (deposit_bonus_min_amount || 0)

    bonus = deposit_amount * (deposit_bonus_percentage || 0) / 100.0
    [bonus, deposit_bonus_max_bonus || 100].min
  end

  # Fill template variables in message strings
  def format_message(template, vars = {})
    result = template.to_s.dup
    vars.each { |k, v| result.gsub!("{#{k}}", v.to_s) }
    result
  end
end
