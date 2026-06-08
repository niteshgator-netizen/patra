# frozen_string_literal: true
#
# Seed Billion Balls (game id 28, slug billion_balls) for account 2.
# Billion Balls exists in the games table but has NO AgentGame and NO GameRule
# for account 2, so Bella can't activate or apply rules for it.
#
# RUN THIS IN RENDER SHELL (production), NOT locally:
#   bundle exec rails runner scripts/seed_billion_balls.rb
#
# Idempotent: uses find_or_create_by, so re-running does nothing harmful.

ACCOUNT_ID = 2
GAME_ID    = 28

game = Game.find_by(id: GAME_ID)
abort("[seed_billion_balls] Game id=#{GAME_ID} not found — aborting") if game.nil?
puts "[seed_billion_balls] Game found: id=#{game.id} slug=#{game.slug} name=#{game.name}"

# 1. AgentGame — links the game to the account so Bella can use the panel.
agent_game = AgentGame.find_or_create_by(account_id: ACCOUNT_ID, game_id: GAME_ID) do |ag|
  ag.status       = 'active'
  ag.credentials  = {}
  ag.display_name = 'Billion Balls'
end
puts "[seed_billion_balls] AgentGame id=#{agent_game.id} status=#{agent_game.status} " \
     "display_name=#{agent_game.display_name.inspect} (new_record persisted=#{agent_game.persisted?})"

# 2. GameRule — defaults matching the other 14 games:
#    freeplay enabled $5, deposit bonus 20%, cashout 4x–10x max $250.
game_rule = GameRule.find_or_create_by(account_id: ACCOUNT_ID, game_id: GAME_ID) do |gr|
  # Freeplay
  gr.freeplay_enabled               = true
  gr.freeplay_amount                = 5.0
  gr.freeplay_max_per_day           = 1
  gr.freeplay_max_per_week          = 3
  gr.freeplay_eligible_tiers        = '["new_player"]'
  gr.freeplay_cashout_min_multiplier = 5.0
  gr.freeplay_cashout_max_amount    = 50.0
  gr.freeplay_require_deposit_first = false
  gr.freeplay_message               = 'fp loaded ✅'

  # Deposit bonus
  gr.deposit_bonus_enabled          = true
  gr.deposit_bonus_percentage       = 20
  gr.deposit_bonus_min_amount       = 10.0
  gr.deposit_bonus_max_bonus        = 100.0
  gr.deposit_bonus_eligible_tiers   = '["all"]'
  gr.deposit_bonus_first_deposit_only = false
  gr.deposit_bonus_message          = 'Loaded with {bonus_pct}% bonus ✅'

  # Cashout
  gr.cashout_enabled                = true
  gr.cashout_min_multiplier         = 4.0
  gr.cashout_max_multiplier         = 10.0
  gr.cashout_max_amount             = 250.0
  gr.cashout_min_amount             = 10.0
  gr.cashout_freeplay_multiplier    = 5.0
  gr.cashout_freeplay_max           = 50.0
  gr.cashout_require_screenshot     = false

  # Links
  gr.auto_send_link_on_create       = true
end
puts "[seed_billion_balls] GameRule id=#{game_rule.id} freeplay_enabled=#{game_rule.freeplay_enabled} " \
     "deposit_bonus_percentage=#{game_rule.deposit_bonus_percentage} " \
     "cashout=#{game_rule.cashout_min_multiplier}x-#{game_rule.cashout_max_multiplier}x " \
     "max=$#{game_rule.cashout_max_amount} (persisted=#{game_rule.persisted?})"

puts '[seed_billion_balls] Done.'
