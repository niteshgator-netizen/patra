# frozen_string_literal: true

# ─────────────────────────────────────────────────────────────────────────────
# PATRA RULES CONSISTENCY CHECK (H2/H4) — READ-ONLY cross-check of every place
# a payment handle or intent label lives, printing every contradiction
# (the $sofiamann8-vs-$shakariyonismack class: Bella telling players a handle
# that is not an active PaymentHandle).
#
#   RUN (Render Shell):  bundle exec rails runner script/patra_rules_consistency_check.rb
#
# Sections:
#   1. Active PaymentHandles (source of truth)
#   2. Handles mentioned in canned responses vs truth
#   3. Handles mentioned in GameRule text columns vs truth
#   4. Handles mentioned in top/approved RAG pair cashier_text vs truth
#      (these are where a wrong handle reaches Bella's mouth)
#   5. RAG_TO_INTENT_MAP coverage vs DISTINCT real_intent labels in the DB
# ─────────────────────────────────────────────────────────────────────────────

ACCOUNT_ID = ENV.fetch('CHECK_ACCOUNT_ID', '2').to_i
HANDLE_RE = /[\$@][a-z0-9][a-z0-9._\-]{2,30}/i

account = Account.find(ACCOUNT_ID)
issues = 0

def section(t) = puts("\n#{'=' * 70}\n#{t}\n#{'=' * 70}")

# ── 1. truth ──────────────────────────────────────────────────────────────────
section('1. ACTIVE PAYMENT HANDLES (source of truth)')
handles = account.payment_handles.to_a
active = handles.select { |h| h.status == 'active' }
truth = active.map { |h| h.normalized_handle }.to_set
active.group_by(&:platform).each do |plat, hs|
  hs.sort_by(&:priority).each do |h|
    cd = h.in_cooldown? ? ' (IN COOLDOWN)' : ''
    puts "  #{plat}: #{h.display_handle} prio=#{h.priority}#{cd}"
  end
end
inactive = handles - active
inactive.each { |h| puts "  [#{h.status}] #{h.platform}: #{h.display_handle}" }
puts '  (none configured!)' if handles.empty?

check_text = lambda do |label, text|
  found = text.to_s.scan(HANDLE_RE).map { |m| m.gsub(/^[\$@]/, '').downcase }.uniq
  bad = found.reject { |f| truth.include?(f) }
  bad.each do |b|
    puts "  ✗ #{label}: mentions '#{b}' — NOT an active handle"
  end
  bad.size
end

# ── 2. canned responses ───────────────────────────────────────────────────────
section('2. CANNED RESPONSES vs active handles')
CannedResponse.where(account_id: ACCOUNT_ID).find_each do |cr|
  issues += check_text.call("canned '#{cr.short_code}'", cr.content)
end
puts '  ✓ no contradictions' if issues.zero?

# ── 3. game rules text ────────────────────────────────────────────────────────
section('3. GAME RULES text columns vs active handles')
gr_issues = 0
text_cols = GameRule.columns.select { |c| %i[text string].include?(c.type) }.map(&:name)
GameRule.where(account_id: ACCOUNT_ID).find_each do |gr|
  text_cols.each do |col|
    gr_issues += check_text.call("game_rule(game_id=#{gr.game_id}).#{col}", gr[col])
  end
end
puts "  checked columns: #{text_cols.join(', ')}"
puts '  ✓ no contradictions' if gr_issues.zero?
issues += gr_issues

# ── 4. RAG pairs (sampled: any cashier_text containing a handle) ─────────────
section('4. RAG PAIRS cashier_text vs active handles (approved, account scope)')
rag_issues = 0
scope = BellaRagPair.for_scope(account_id: ACCOUNT_ID)
                    .where("cashier_text ~* '[\\$@][a-z0-9]'")
total_with_handles = scope.count
offenders = Hash.new(0)
scope.find_each do |pair|
  pair.cashier_text.to_s.scan(HANDLE_RE).map { |m| m.gsub(/^[\$@]/, '').downcase }.uniq.each do |f|
    offenders[f] += 1 unless truth.include?(f)
  end
end
puts "  pairs containing a $/@ handle: #{total_with_handles}"
if offenders.empty?
  puts '  ✓ no stale handles in RAG pairs'
else
  offenders.sort_by { |_, c| -c }.each do |h, c|
    puts "  ✗ RAG pairs mention '#{h}' #{c}x — NOT an active handle (Bella may quote it verbatim via RAG examples)"
    rag_issues += 1
  end
end
issues += rag_issues

# ── 5. RAG_TO_INTENT_MAP coverage ────────────────────────────────────────────
section('5. RAG_TO_INTENT_MAP coverage vs DB real_intent labels')
db_labels = BellaRagPair.where.not(real_intent: nil).distinct.pluck(:real_intent).sort
map_keys = Games::ConversationOrchestrator::RAG_TO_INTENT_MAP.keys
unmapped = db_labels - map_keys
extra = map_keys - db_labels
puts "  DB labels: #{db_labels.size} · mapped: #{map_keys.size}"
if unmapped.any?
  unmapped.each do |l|
    n = BellaRagPair.where(real_intent: l).count
    puts "  ✗ UNMAPPED label '#{l}' (#{n} pairs) — RAG cutover returns nil for these"
    issues += 1
  end
else
  puts '  ✓ every DB label is mapped'
end
extra.each { |l| puts "  (map key '#{l}' has no DB pairs yet — harmless)" }

# ── summary ───────────────────────────────────────────────────────────────────
section("RESULT: #{issues.zero? ? 'CONSISTENT' : "#{issues} CONTRADICTION(S)"}")
puts 'Read-only run — nothing modified.'
exit(issues.zero? ? 0 : 1)
