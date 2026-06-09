# frozen_string_literal: true

# ─────────────────────────────────────────────────────────────────────────────
# PATRA GAME CONNECTIVITY CHECK — read-only probe of every game integration.
# For account 2, for each agent_game with an API client, calls the existing
# READ-ONLY test_connection (which reads agent_balance — NO money moves, NO
# player created, NO recharge/withdraw/reset). Reports ✓ CONNECTED / ✗ FAILED
# with the real error, so we know which integrations actually connect at launch.
#
#   RUN (Render Shell):  bundle exec rails runner script/patra_game_connectivity_check.rb
#
# STRICTLY READ-ONLY: the ONLY client method called is test_connection. It never
# calls add_user / recharge / withdraw / reset_player_password / force_player_offline.
# Each game is wrapped in begin/rescue so one panel's exception never kills the run.
# No Telegram, no writes, no deploy.
#
# test_connection bodies (verified read-only, Phase 0):
#   AspNetPanel::BaseClient  GET search page → scrape agent balance  (fire_kirin, milky_way, orion_stars, panda_master)
#   LaravelPanel::BaseClient agent_balance → POST /api/agent/getMoney (cash_machine, game_room, mafia, mr_all_in_one)
#   FastApi::Client          agent_login → returns balance            (ultra_panda, vblink)
#   GameVault::Client        agent_balance → POST /api/external/agentBalance (game_vault, juwa2, vegas_sweeps)
#   Juwa::Client             agent_balance → raw_post('agentBalance')  (juwa)
# ─────────────────────────────────────────────────────────────────────────────

ACCOUNT_ID = 2

line = '=' * 76
puts line
puts "PATRA GAME CONNECTIVITY CHECK  (account #{ACCOUNT_ID}, read-only test_connection)"
puts line

agent_games = AgentGame.for_account(ACCOUNT_ID).includes(:game).to_a
# stable, readable order
agent_games.sort_by! { |ag| ag.game&.name.to_s.downcase }

puts "Loaded #{agent_games.size} agent_game(s) for account #{ACCOUNT_ID}.\n"

summary = { total: agent_games.size, with_client: 0, connected: 0, failed: [], skipped: [] }

agent_games.each do |ag|
  game   = ag.game
  name   = game&.name || '(no game record)'
  slug   = game&.slug.to_s
  has_api = game&.has_api? ? true : false
  status = ag.status

  puts "\n#{'-' * 76}"
  puts "[agent_game ##{ag.id}] #{name}  (slug=#{slug.empty? ? '?' : slug})  has_api=#{has_api}  status=#{status}"

  # Skip cleanly: no slug, game not API-enabled, or slug has no registered client.
  if slug.empty?
    puts '  — no game slug (skip)'
    summary[:skipped] << "#{name} (no slug)"
    next
  end
  unless has_api
    puts '  — game not API-enabled (has_api=false) (skip)'
    summary[:skipped] << "#{name} (has_api=false)"
    next
  end
  unless Games::ClientRegistry.supported?(slug)
    puts "  — no API client registered for '#{slug}' (skip)"
    summary[:skipped] << "#{name} (unsupported slug #{slug})"
    next
  end

  summary[:with_client] += 1

  begin
    client = Games::ClientRegistry.client_for(ag)
    if client.nil?
      puts '  ✗ FAILED — ClientRegistry.client_for returned nil'
      summary[:failed] << [name, 'client_for returned nil']
      next
    end

    result = client.test_connection # READ-ONLY: reads agent_balance only
    if result.is_a?(Hash) && result[:ok]
      bal = result[:balance]
      summary[:connected] += 1
      puts "  ✓ CONNECTED — agent_balance=#{bal.nil? ? '(blank)' : "$#{bal}"}  msg=#{result[:message]}"
    else
      code = result.is_a?(Hash) ? result[:code] : '?'
      msg  = result.is_a?(Hash) ? result[:message] : result.inspect
      puts "  ✗ FAILED — code=#{code}  msg=#{msg}"
      summary[:failed] << [name, "code=#{code} #{msg}"]
    end
  rescue StandardError => e
    # test_connection should rescue internally, but the client constructor (e.g.
    # missing-credential ArgumentError) can raise — catch it so the run continues.
    puts "  ✗ FAILED — raised #{e.class}: #{e.message}"
    summary[:failed] << [name, "#{e.class}: #{e.message}"]
  end
end

# ── summary ───────────────────────────────────────────────────────────────────
puts "\n#{line}"
puts 'SUMMARY'
puts line
puts "Total agent_games:      #{summary[:total]}"
puts "With an API client:     #{summary[:with_client]}"
puts "✓ CONNECTED:            #{summary[:connected]}"
puts "✗ FAILED:               #{summary[:failed].size}"
puts "Skipped (no client):    #{summary[:skipped].size}"

unless summary[:failed].empty?
  puts "\nFAILED games (the diagnostic — fix these before launch):"
  summary[:failed].each { |nm, err| puts "  ✗ #{nm}: #{err}" }
end

unless summary[:skipped].empty?
  puts "\nSkipped:"
  summary[:skipped].each { |s| puts "  — #{s}" }
end

puts "\nHEALTHY = most games ✓ CONNECTED with a balance. EXPECTED FAILURES per notes:"
puts "  Game Vault (invalid/expired token), Vegas Sweeps (URL pending), Juwa (silent-fail)."
puts line
