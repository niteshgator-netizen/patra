# frozen_string_literal: true

# ─────────────────────────────────────────────────────────────────────────────
# PATRA — deactivate ACTIVE catalog games that have NO panel client integration.
#
#   PLAN (read-only, default):
#     bundle exec rails runner script/patra_deactivate_clientless_games.rb
#   EXECUTE:
#     bundle exec rails runner script/patra_deactivate_clientless_games.rb --confirm
#
# A game is "clientless" when its slug has no entry in
# Games::ClientRegistry::REGISTRY — Bella/ActionExecutor can never load or
# cash out on it ("Game <slug> not yet integrated"). Leaving them active only
# creates dead UI choices and orchestrator escalations.
#
# Idempotent: only flips status 'active' -> 'deprecated'; rerun finds nothing.
# Never touches games that HAVE a client, never deletes anything.
# ─────────────────────────────────────────────────────────────────────────────

confirm = ARGV.include?('--confirm')

supported = Games::ClientRegistry.supported_slugs
clientless = Game.active.reject { |g| supported.include?(g.slug.to_s) }

puts '=' * 72
puts "PATRA — deactivate clientless games (#{confirm ? 'EXECUTE --confirm' : 'PLAN ONLY — pass --confirm to apply'})"
puts '=' * 72
puts "ClientRegistry slugs (#{supported.size}): #{supported.sort.join(', ')}"
puts "Active catalog games: #{Game.active.count} · clientless among them: #{clientless.size}"
puts

if clientless.empty?
  puts 'Nothing to do — every active game has a client (or all clientless ones already deprecated).'
  exit 0
end

puts 'PLAN — these games would be set status active -> deprecated:'
clientless.each do |g|
  ag_count = g.agent_games.count
  flag = ag_count.positive? ? "  ⚠ #{ag_count} agent_game(s) configured — their panels will stop being offered" : ''
  puts format('  - %-22s id=%-4d has_api=%-5s agent_games=%d%s', g.slug, g.id, g.has_api, ag_count, flag)
end
puts

unless confirm
  puts "DRY RUN — no changes made. Re-run with --confirm to apply."
  exit 0
end

changed = 0
clientless.each do |g|
  next unless g.status == 'active' # idempotency belt-and-braces

  g.update!(status: 'deprecated')
  changed += 1
  puts "  deprecated: #{g.slug} (id=#{g.id})"
rescue StandardError => e
  puts "  FAILED #{g.slug}: #{e.class}: #{e.message}"
end

puts
puts "DONE — #{changed} game(s) deprecated. Re-run without --confirm to verify plan is now empty."
