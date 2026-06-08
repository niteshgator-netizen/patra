# frozen_string_literal: true

# ─────────────────────────────────────────────────────────────────────────────
# PATRA BRAIN STRESS-TEST — grades the LIVE regex intent detector against every
# real customer message in bella_rag_pairs (all labelled with real_intent).
#
#   RUN (Render Shell):  bundle exec rails runner script/patra_brain_stress_test.rb
#
# READ-ONLY. It only READS bella_rag_pairs and CALLS Games::IntentDetector.detect.
# No DB writes, no replies, no Telegram, no money, no network (detect is pure
# regex/keyword — verified: it makes zero HTTP/embedding calls).
#
# Grading is apples-to-apples across two label spaces:
#   real_intent (string, the answer key)  --RAG_TO_INTENT_MAP-->  expected SYMBOL
#   detect(customer_text)[:intent]                            =   actual   SYMBOL
#   HIT iff actual == expected.
#
# NOTE (reported, not fudged): 3 mapped real_intents map to symbols the REGEX
# detector cannot produce (new_account_reissue, redeem_partial_replay,
# replay_from_balance) — those are RAG-cutover-only intents, so they score ~0%
# here BY DESIGN. They're flagged [RAG-only] in the output.
# ─────────────────────────────────────────────────────────────────────────────

ACCOUNT_ID    = 2
BATCH_SIZE    = 2000
PROGRESS_EVERY = 5000
SAMPLES_PER_INTENT = 8
NIL_SYM       = :__nil__   # placeholder for "detect returned nil / no intent"

# Symbols the regex detector can actually emit (every branch of detect). Used only
# to annotate which mapped intents are unreachable by regex (RAG-only).
PRODUCIBLE_SYMBOLS = %i[
  greeting status_check request_multi_account_creation request_account_creation
  reset_password cashout_rules cashout load_freeplay load_bonus load
  payment_method_chosen payment_sent_confirmation complaint_angry tech_issue
  balance_check transfer_between_games whats_hitting referral
  payment_method_question request_download_link request_app_link
  request_game_link list_platforms username_provided
].freeze

# Quiet the detector's per-message Rails.logger.info spam (73k calls). Process-local
# runtime setting only — touches no code/file.
Rails.logger.level = Logger::ERROR

expected_map = Games::ConversationOrchestrator::RAG_TO_INTENT_MAP
puts "[stress] RAG_TO_INTENT_MAP entries: #{expected_map.size}"
puts "[stress] unmapped truths (bucketed separately): greeting_chitchat, unclear"

# ── accumulators (all bounded by ~30 intents — memory stays flat) ─────────────
per_intent  = Hash.new { |h, k| h[k] = { total: 0, hits: 0, wrong: Hash.new(0) } }
confusion   = Hash.new(0)                       # [expected_sym, actual_sym] => count (mismatches only)
conf_stats  = Hash.new { |h, k| h[k] = { total: 0, hits: 0 } }   # high/medium/low => {total,hits}
unmapped    = Hash.new { |h, k| h[k] = { total: 0, actual: Hash.new(0), appropriate: 0 } }
samples     = Hash.new { |h, k| h[k] = [] }     # real_intent => [{text, expected, actual}] (capped)

graded = hits = miss = nil_count = unmapped_total = err_count = blank_text = 0
processed = 0
started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
first_batch_logged = false

def conf_bucket(val)
  return 'unknown' if val.nil?
  if val.is_a?(Numeric)
    return 'high'   if val >= 0.8
    return 'medium' if val >= 0.5
    'low'
  else
    s = val.to_s.strip.downcase
    %w[high medium low].include?(s) ? s : (s.empty? ? 'unknown' : s)
  end
end

scope = BellaRagPair.where(account_id: ACCOUNT_ID)
                    .where.not(real_intent: nil)
                    .select(:id, :customer_text, :real_intent, :real_intent_confidence)

total_rows = scope.count
puts "[stress] grading #{total_rows} rows (account_id=#{ACCOUNT_ID}, real_intent present)…"

scope.find_each(batch_size: BATCH_SIZE) do |row|
  processed += 1
  text = row.customer_text.to_s
  blank_text += 1 if text.strip.empty?
  real = row.real_intent.to_s

  # Call the live detector. Never let one bad row kill the run.
  actual =
    begin
      res = Games::IntentDetector.detect(text)
      res.is_a?(Hash) ? res[:intent] : nil
    rescue StandardError => e
      err_count += 1
      Rails.logger.error("[stress] detect raised on row #{row.id}: #{e.class}: #{e.message}")
      nil
    end
  actual_key = actual || NIL_SYM

  if expected_map.key?(real)
    # ── MAPPED truth → real pass/fail grading ──
    expected = expected_map[real]
    graded += 1
    nil_count += 1 if actual.nil?
    bucket = conf_bucket(row.real_intent_confidence)
    conf_stats[bucket][:total] += 1

    stat = per_intent[real]
    stat[:total] += 1
    if actual == expected
      hits += 1
      stat[:hits] += 1
      conf_stats[bucket][:hits] += 1
    else
      miss += 1
      stat[:wrong][actual_key] += 1
      confusion[[expected, actual_key]] += 1
      if samples[real].size < SAMPLES_PER_INTENT
        samples[real] << { text: text[0, 160], expected: expected, actual: actual_key }
      end
    end
  else
    # ── UNMAPPED truth (greeting_chitchat / unclear) → informational bucket ──
    unmapped_total += 1
    u = unmapped[real]
    u[:total] += 1
    u[:actual][actual_key] += 1
    # "Appropriate" = the brain did NOT misroute to a concrete action:
    #   greeting_chitchat -> nil OR :greeting ;  everything else (unclear) -> nil
    appropriate =
      if real == 'greeting_chitchat'
        actual.nil? || actual == :greeting
      else
        actual.nil?
      end
    u[:appropriate] += 1 if appropriate
  end

  if (processed % PROGRESS_EVERY).zero?
    elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - started
    rate = processed / elapsed
    eta = total_rows.positive? ? ((total_rows - processed) / rate) : 0
    puts format('[stress] %d/%d processed (%.0f rows/s, ~%.0fs left)', processed, total_rows, rate, eta)
  end

  unless first_batch_logged
    if processed >= BATCH_SIZE
      first_batch_logged = true
      elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - started
      puts format('[stress] first %d rows in %.1fs (%.0f rows/s) — detect is pure-Ruby, full run projected ~%.0fs',
                  processed, elapsed, processed / elapsed, total_rows / (processed / elapsed))
    end
  end
end

elapsed_total = Process.clock_gettime(Process::CLOCK_MONOTONIC) - started

# ─────────────────────────────────────────────────────────────────────────────
#  REPORT
# ─────────────────────────────────────────────────────────────────────────────
def pct(num, den)
  den.zero? ? 0.0 : (num.to_f / den * 100)
end

def rag_only?(sym)
  !PRODUCIBLE_SYMBOLS.include?(sym)
end

line = '=' * 78
puts "\n#{line}\nPATRA BRAIN STRESS-TEST REPORT\n#{line}"

# 1. HEADLINE
puts "\n[1] HEADLINE"
puts "  rows processed      : #{processed}"
puts "  mapped (graded)     : #{graded}"
puts format('  overall accuracy    : %.2f%%  (%d hits / %d mapped)', pct(hits, graded), hits, graded)
puts "  hits                : #{hits}"
puts "  misses              : #{miss}"
puts "  detect returned nil : #{nil_count}  (counted as miss against mapped truth)"
puts "  unmapped-truth rows : #{unmapped_total}  (greeting_chitchat / unclear — bucketed, NOT in accuracy)"
puts "  blank customer_text : #{blank_text}"
puts "  detect errors       : #{err_count}"
puts format('  wall time           : %.1fs (%.0f rows/s)', elapsed_total, processed / [elapsed_total, 0.0001].max)

# 2. PER-INTENT TABLE (by row count DESC)
puts "\n[2] PER-INTENT ACCURACY (mapped truths, by volume DESC)"
puts format('  %-26s %7s %7s %8s   %s', 'real_intent', 'total', 'hits', 'acc%', 'top wrong symbols brain gave')
per_intent.sort_by { |_, s| -s[:total] }.each do |real, s|
  expected = expected_map[real]
  flag = rag_only?(expected) ? ' [RAG-only]' : ''
  top_wrong = s[:wrong].sort_by { |_, c| -c }.first(3)
                       .map { |sym, c| "#{sym}×#{c}" }.join(', ')
  puts format('  %-26s %7d %7d %7.1f%%   %s%s',
              real, s[:total], s[:hits], pct(s[:hits], s[:total]), top_wrong, flag)
end

# 3. CONFUSION HOTSPOTS (top 15 expected→actual mismatch pairs)
puts "\n[3] CONFUSION HOTSPOTS (top 15 expected → actual mismatches by volume)"
confusion.sort_by { |_, c| -c }.first(15).each do |(exp, act), c|
  puts format('  %-26s -> %-26s %6d', exp, act, c)
end

# 4. WORST INTENTS (lowest accuracy, >= 100 rows) — the build priority list
puts "\n[4] WORST INTENTS (>=100 rows, lowest accuracy first) — fix these"
worst = per_intent.select { |_, s| s[:total] >= 100 }
                  .sort_by { |_, s| pct(s[:hits], s[:total]) }
worst.first(10).each do |real, s|
  flag = rag_only?(expected_map[real]) ? ' [RAG-only — regex cannot emit this; caught by RAG cutover, not this test]' : ''
  puts format('  %-26s %6.1f%%  (%d/%d)%s', real, pct(s[:hits], s[:total]), s[:hits], s[:total], flag)
end

# 5. SAMPLES for the 5 worst (excluding RAG-only, since those are 0% by design)
puts "\n[5] MISROUTE SAMPLES — 5 worst REGEX-reachable intents"
worst.reject { |real, _| rag_only?(expected_map[real]) }.first(5).each do |real, s|
  puts "\n  ── #{real}  (#{pct(s[:hits], s[:total]).round(1)}%, #{s[:hits]}/#{s[:total]})  expected=#{expected_map[real]}"
  samples[real].first(5).each do |ex|
    puts format('     brain=%-24s | %s', ex[:actual], ex[:text].gsub(/\s+/, ' '))
  end
end

# 6. CONFIDENCE BREAKDOWN
puts "\n[6] ACCURACY BY real_intent_confidence (mapped rows)"
%w[high medium low unknown].each do |b|
  next unless conf_stats.key?(b)
  s = conf_stats[b]
  puts format('  %-8s %7.2f%%  (%d/%d)', b, pct(s[:hits], s[:total]), s[:hits], s[:total])
end
# any non-standard buckets
conf_stats.keys.reject { |k| %w[high medium low unknown].include?(k) }.each do |b|
  s = conf_stats[b]
  puts format('  %-8s %7.2f%%  (%d/%d)', b, pct(s[:hits], s[:total]), s[:hits], s[:total])
end

# UNMAPPED-TRUTH detail (informational)
puts "\n[+] UNMAPPED-TRUTH BUCKET (greeting_chitchat / unclear — informational)"
unmapped.sort_by { |_, u| -u[:total] }.each do |real, u|
  appr = pct(u[:appropriate], u[:total])
  top = u[:actual].sort_by { |_, c| -c }.first(4).map { |sym, c| "#{sym}×#{c}" }.join(', ')
  rule = real == 'greeting_chitchat' ? '(appropriate = nil or :greeting)' : '(appropriate = nil)'
  puts format('  %-18s total=%d  appropriate=%.1f%% %s', real, u[:total], appr, rule)
  puts "      brain said: #{top}"
end

puts "\n#{line}\n[stress] done.\n#{line}"
