# frozen_string_literal: true

# READ-ONLY data integrity sweep for Patra launch night.
# Run on Render Shell:   bundle exec rails runner script/patra_data_integrity.rb
# (or locally with a prod DATABASE_URL — it only ever SELECTs).
#
# Checks:
#   1. finance-log entry shapes across contacts (patra_finance_logs)
#   2. orphaned / stuck cashier claims
#   3. AgentGame completeness (incl. Billion Ballas AgentGame 21)
#   4. GameRule completeness (incl. GameRule 17) — every active panel has rules
#   5. game-credential key hygiene on contacts (game_username_<slug> orphans)

ACCOUNT_ID = ENV.fetch('PATRA_ACCOUNT_ID', '2').to_i
issues = Hash.new(0)
puts "\n#{'=' * 72}\nPATRA DATA INTEGRITY (read-only)  account=#{ACCOUNT_ID}  #{Time.current}\n#{'=' * 72}"

def section(t)
  puts "\n#{'-' * 72}\n#{t}\n#{'-' * 72}"
end

# ── 1. finance-log shapes ────────────────────────────────────────────────────
section('1. patra_finance_logs entry shapes')
checked = 0
bad_shape = []
Contact.where(account_id: ACCOUNT_ID)
       .where("custom_attributes ? 'patra_finance_logs'")
       .find_each do |c|
  checked += 1
  logs = c.custom_attributes['patra_finance_logs']
  unless logs.is_a?(Array)
    bad_shape << "contact=#{c.id} logs is #{logs.class}, expected Array"
    next
  end
  logs.each_with_index do |entry, i|
    next if entry.is_a?(Hash) && entry['amount'].present? && entry['status'].present?

    bad_shape << "contact=#{c.id} entry[#{i}] malformed: #{entry.inspect[0, 120]}"
  end
end
puts "contacts with finance logs: #{checked}"
if bad_shape.any?
  issues[:finance_logs] = bad_shape.size
  bad_shape.first(20).each { |b| puts "  BAD: #{b}" }
  puts "  ... and #{bad_shape.size - 20} more" if bad_shape.size > 20
else
  puts 'OK — all entries are Hashes with amount + status'
end

# ── 2. cashier claims ────────────────────────────────────────────────────────
section('2. cashier claims')
total = CashierClaim.where(account_id: ACCOUNT_ID).count
stuck = CashierClaim.where(account_id: ACCOUNT_ID, status: 'pending')
                    .where('expires_at < ?', 1.hour.ago).count
orphan_conv = CashierClaim.where(account_id: ACCOUNT_ID)
                          .where.not(conversation_id: Conversation.where(account_id: ACCOUNT_ID).select(:id)).count
orphan_contact = CashierClaim.where(account_id: ACCOUNT_ID)
                             .where.not(contact_id: Contact.where(account_id: ACCOUNT_ID).select(:id)).count
claimed_never_done = CashierClaim.where(account_id: ACCOUNT_ID, status: 'claimed')
                                 .where('claimed_at < ?', 24.hours.ago).count
puts "total=#{total}"
puts "pending past expiry >1h (expiry job may be dead): #{stuck}"
puts "orphaned conversation refs: #{orphan_conv}"
puts "orphaned contact refs: #{orphan_contact}"
puts "claimed >24h never completed: #{claimed_never_done}"
issues[:cashier_claims] = stuck + orphan_conv + orphan_contact

# ── 3. agent games ───────────────────────────────────────────────────────────
section('3. agent games (panels)')
AgentGame.where(account_id: ACCOUNT_ID).includes(:game).find_each do |ag|
  problems = []
  problems << 'no game row' if ag.game.nil?
  problems << 'credentials not a hash' unless ag.credentials.is_a?(Hash)
  if ag.status == 'active' && ag.game&.has_api
    missing = ag.game.required_field_names.reject { |k| ag.credentials.to_h[k].present? }
    problems << "missing credential fields: #{missing.join(',')}" if missing.any?
  end
  problems << "degraded (failures=#{ag.failure_count})" if ag.status == 'degraded'
  next if problems.empty?

  issues[:agent_games] += 1
  puts "  AgentGame #{ag.id} (#{ag.game&.slug || '?'}, #{ag.status}): #{problems.join('; ')}"
end
bb = AgentGame.find_by(id: 21)
puts bb ? "AgentGame 21 (Billion Ballas): present, game=#{bb.game&.slug}, status=#{bb.status}" : 'MISSING: AgentGame 21 (Billion Ballas)'
issues[:agent_games] += 1 if bb.nil?
puts 'OK — no panel problems' if issues[:agent_games].zero?

# ── 4. game rules ────────────────────────────────────────────────────────────
section('4. game rules')
gr17 = GameRule.find_by(id: 17)
puts gr17 ? "GameRule 17: present, game=#{gr17.game&.slug}, account=#{gr17.account_id}" : 'MISSING: GameRule 17 (Billion Ballas)'
issues[:game_rules] += 1 if gr17.nil?
AgentGame.where(account_id: ACCOUNT_ID, status: 'active').includes(:game).find_each do |ag|
  next if ag.game.nil?
  next if GameRule.exists?(account_id: ACCOUNT_ID, game_id: ag.game_id)

  issues[:game_rules] += 1
  puts "  ACTIVE panel without GameRule: #{ag.game.slug} (agent_game=#{ag.id}) — cashout mins fall back to code defaults"
end
puts 'OK — every active panel has rules' if issues[:game_rules].zero?

# ── 5. contact game-credential hygiene ──────────────────────────────────────
section('5. contact game_username_<slug> hygiene')
known_slugs = Game.pluck(:slug).map(&:downcase)
unknown = Hash.new(0)
Contact.where(account_id: ACCOUNT_ID)
       .where("custom_attributes::text LIKE '%game_username_%'")
       .find_each do |c|
  c.custom_attributes.to_h.each_key do |k|
    next unless k.start_with?('game_username_')

    slug = k.sub('game_username_', '').downcase
    unknown[slug] += 1 unless known_slugs.include?(slug)
  end
end
if unknown.any?
  unknown.each { |slug, n| puts "  unknown slug '#{slug}' on #{n} contacts (won't match any panel)" }
  issues[:cred_keys] = unknown.values.sum
else
  puts 'OK — every stored game_username key maps to a known game slug'
end

# ── summary ──────────────────────────────────────────────────────────────────
section('SUMMARY')
if issues.values.sum.zero?
  puts 'ALL CLEAN ✅'
else
  issues.each { |k, v| puts format('%-16s %d issue(s)', k, v) }
  puts "\nThis script is READ-ONLY — nothing was changed."
end
