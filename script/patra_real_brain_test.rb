# frozen_string_literal: true

# ─────────────────────────────────────────────────────────────────────────────
# PATRA REAL BRAIN TEST — true accuracy = regex hits + RAG rescues, exactly the
# way the orchestrator routes (regex first; if nil, RAG at confidence >= 0.60 with
# a mapped label). Honest LEAVE-ONE-OUT: every test row is itself a bella_rag_pair,
# so the RAG search EXCLUDES the row's own id (else it self-matches at distance 0).
#
#   RUN (Render Shell):  bundle exec rails runner script/patra_real_brain_test.rb
#
# READ-ONLY. Reads bella_rag_pairs, calls Games::IntentDetector.detect, and embeds
# regex-miss rows via Voyage (the only network calls). No writes, no Telegram, no
# replies, no money.
# ─────────────────────────────────────────────────────────────────────────────

SAMPLE_SIZE   = 2000      # bump this to widen the sample
STRATA_FLOOR  = 20        # min rows sampled per real_intent (if available) so rare intents show
ACCOUNT_ID    = 2
INDUSTRY_SLUG = 'sweepstakes'
CUTOVER       = 0.60      # orchestrator's HARDCODED live RAG cutover (conv_orchestrator.rb:205)
LOAD_BATCH    = 500

# Pull predict's constants from the real class so the inline replica CANNOT drift.
IR = BellaRag::IntentRetriever
TOP_K          = IR::TOP_K                  # 10
MIN_SIMILARITY = IR::MIN_SIMILARITY         # 0.30
CONF_THRESHOLD = IR::CONFIDENCE_THRESHOLD   # 0.35
MAX_TEXT_CHARS = IR::MAX_TEXT_CHARS         # 512

EXPECTED_MAP = Games::ConversationOrchestrator::RAG_TO_INTENT_MAP

Rails.logger.level = Logger::ERROR   # silence detector/RAG per-call log spam

@embed_calls = 0

# Inline leave-one-out RAG — byte-for-byte predict's math (same constants, same
# for_scope, same weighted vote, same confidence) PLUS `.where.not(id: exclude_id)`.
def inline_predict_loo(text, exclude_id)
  return nil if text.blank?

  @embed_calls += 1
  query_vec = Bella::VoyageEmbedder.embed_one(text.to_s.slice(0, MAX_TEXT_CHARS), input_type: 'query')
  return nil if query_vec.blank?

  rows = BellaRagPair
           .for_scope(account_id: ACCOUNT_ID, industry_slug: INDUSTRY_SLUG)
           .where.not(real_intent: nil)
           .where.not(id: exclude_id)                      # ← LEAVE-ONE-OUT
           .nearest_neighbors(:embedding, query_vec, distance: 'cosine')
           .limit(TOP_K)
           .to_a
  return nil if rows.empty?

  votes = Hash.new(0.0)
  rows.each do |row|
    similarity = 1.0 - row.neighbor_distance.to_f
    next if similarity < MIN_SIMILARITY
    votes[row.real_intent] += similarity
  end
  return nil if votes.empty?

  total_weight = votes.values.sum
  best_intent, best_weight = votes.max_by { |_, w| w }
  confidence = total_weight > 0 ? (best_weight / total_weight).round(3) : 0.0
  return nil if confidence < CONF_THRESHOLD

  { intent: best_intent, confidence: confidence }
rescue StandardError => e
  Rails.logger.error("[realbrain] inline RAG failed (id=#{exclude_id}): #{e.class}: #{e.message}")
  nil
end

def pct(num, den)
  den.zero? ? 0.0 : (num.to_f / den * 100)
end

# ── STRATIFIED SAMPLE (proportional per real_intent, floor STRATA_FLOOR) ───────
base = BellaRagPair.where(account_id: ACCOUNT_ID).where.not(real_intent: nil)
counts = base.group(:real_intent).count
total_pop = counts.values.sum
puts "[realbrain] population: #{total_pop} labelled rows across #{counts.size} real_intents"

sample_ids = []
counts.each do |intent, cnt|
  target = [[(SAMPLE_SIZE * cnt.to_f / total_pop).round, STRATA_FLOOR].max, cnt].min
  ids = base.where(real_intent: intent).order(Arel.sql('RANDOM()')).limit(target).pluck(:id)
  sample_ids.concat(ids)
end
sample_ids.shuffle!
puts "[realbrain] stratified sample (proportional, floor #{STRATA_FLOOR}/intent): #{sample_ids.size} rows"
puts "[realbrain] live cutover=#{CUTOVER}  (TOP_K=#{TOP_K} MIN_SIM=#{MIN_SIMILARITY} CONF=#{CONF_THRESHOLD})"

# ── accumulators ──────────────────────────────────────────────────────────────
paths       = Hash.new(0)                                   # regex / rag_routed / rag_below_cutover / rag_nil
regex_total = 0; regex_hits = 0
main_total  = 0; main_hits  = 0                             # mapped-truth rows only
rag_rescue_total = 0; rag_rescue_hits = 0                   # regex-miss mapped rows that routed via RAG
per_intent  = Hash.new { |h, k| h[k] = { total: 0, hits: 0 } }
unmapped    = Hash.new { |h, k| h[k] = { total: 0, final: Hash.new(0) } }
rescue_data = []                                            # regex-miss mapped rows w/ a RAG label: {conf, mapped_label, expected}
rag_nil_mapped = 0                                          # regex-miss mapped rows where predict returned nil
samples     = Hash.new { |h, k| h[k] = [] }                # genuinely-unhandled examples per intent
processed   = 0
started     = Process.clock_gettime(Process::CLOCK_MONOTONIC)

sample_ids.each_slice(LOAD_BATCH) do |batch_ids|
  BellaRagPair.where(id: batch_ids)
              .select(:id, :customer_text, :real_intent, :real_intent_confidence)
              .each do |row|
    processed += 1
    text = row.customer_text.to_s
    real = row.real_intent.to_s
    expected = EXPECTED_MAP[real]

    # 1) Regex first
    regex = Games::IntentDetector.detect(text)
    regex_intent = regex.is_a?(Hash) ? regex[:intent] : nil

    final = nil
    path  = nil
    rag_label = nil
    rag_conf  = nil

    if regex_intent
      final = regex_intent
      path  = 'regex'
    else
      rag = inline_predict_loo(text, row.id)
      if rag.nil?
        path = 'rag_nil'
      else
        rag_label = rag[:intent]
        rag_conf  = rag[:confidence]
        mapped    = EXPECTED_MAP[rag_label]
        if rag_conf >= CUTOVER && mapped
          final = mapped
          path  = 'rag_routed'
        else
          path = 'rag_below_cutover'
        end
      end
    end
    paths[path] += 1

    # 2) Grade (mapped truths only; unmapped greeting_chitchat/unclear bucketed)
    if expected.nil?
      u = unmapped[real]
      u[:total] += 1
      u[:final][final || :__nil__] += 1
    else
      main_total += 1
      hit = (final == expected)
      main_hits += 1 if hit
      per_intent[real][:total] += 1
      per_intent[real][:hits]  += 1 if hit

      if path == 'regex'
        regex_total += 1
        regex_hits  += 1 if hit
      else
        # regex missed → this row's correctness depends on RAG
        if rag_label
          mapped_label = EXPECTED_MAP[rag_label]
          rescue_data << { conf: rag_conf, mapped_label: mapped_label, expected: expected }
          if path == 'rag_routed'
            rag_rescue_total += 1
            rag_rescue_hits  += 1 if hit
          end
        else
          rag_nil_mapped += 1
        end
      end

      # collect genuinely-unhandled samples: full brain wrong AND regex missed
      if !hit && regex_intent.nil? && samples[real].size < 8
        samples[real] << {
          text: text[0, 160].gsub(/\s+/, ' '),
          final: final || :__nil__,
          rag_label: rag_label, rag_conf: rag_conf, path: path
        }
      end
    end

    if (@embed_calls % 200).zero? && @embed_calls.positive?
      el = Process.clock_gettime(Process::CLOCK_MONOTONIC) - started
      puts format('[realbrain] %d processed, %d embeddings (%.1fs elapsed)', processed, @embed_calls, el)
    end
  end
end

elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - started

# ─────────────────────────────────────────────────────────────────────────────
#  REPORT
# ─────────────────────────────────────────────────────────────────────────────
line = '=' * 78
puts "\n#{line}\nPATRA REAL BRAIN TEST — regex + RAG (leave-one-out)\n#{line}"

# 1. HEADLINE
puts "\n[1] HEADLINE"
puts "  sample rows graded (mapped): #{main_total}   (+#{unmapped.values.sum { |u| u[:total] }} unmapped-truth, bucketed)"
puts format('  TRUE accuracy (regex+RAG)  : %.2f%%  (%d / %d)', pct(main_hits, main_total), main_hits, main_total)
puts format('    regex-hit accuracy       : %.2f%%  (%d / %d)', pct(regex_hits, regex_total), regex_hits, regex_total)
puts format('    RAG-rescue accuracy      : %.2f%%  (%d / %d routed)', pct(rag_rescue_hits, rag_rescue_total), rag_rescue_hits, rag_rescue_total)
puts "  path split (of full sample):"
%w[regex rag_routed rag_below_cutover rag_nil].each do |p|
  puts format('    %-18s %6d  (%.1f%%)', p, paths[p], pct(paths[p], processed))
end
puts "  embedding calls made       : #{@embed_calls}"
puts format('  wall time                  : %.1fs', elapsed)

# 2. THE MONEY QUESTION
regex_miss_mapped = main_total - regex_total
puts "\n[2] THE MONEY QUESTION — of mapped rows REGEX missed (#{regex_miss_mapped}), how many did RAG correctly rescue at the live #{CUTOVER} gate?"
puts format('    correctly rescued : %d  (%.1f%% of regex-misses)', rag_rescue_hits, pct(rag_rescue_hits, regex_miss_mapped))
puts format('    regex hits        : %d', regex_hits)
puts format('    => full-brain hits: %d / %d = %.2f%%   (vs regex-only %.2f%%)',
            main_hits, main_total, pct(main_hits, main_total), pct(regex_hits, main_total))

# 3. FINDING-2 TUNING TABLE
puts "\n[3] FINDING-2 — RAG label correctness vs confidence (regex-miss mapped rows)"
lost  = rescue_data.count { |d| d[:mapped_label] == d[:expected] && d[:conf] >= 0.35 && d[:conf] < 0.60 }
kept  = rescue_data.count { |d| d[:mapped_label] == d[:expected] && d[:conf] >= 0.60 }
wrong = rescue_data.count { |d| d[:mapped_label] != d[:expected] }
puts "    RAG predicted CORRECT label, conf [0.35,0.60) : #{lost}   (LOST by the 0.60 gate)"
puts "    RAG predicted CORRECT label, conf [0.60,1.00] : #{kept}   (kept / routed right)"
puts "    RAG predicted WRONG label (any conf)          : #{wrong}"
puts "    RAG returned nil (no label, below 0.35 floor) : #{rag_nil_mapped}"
puts "\n    Would-be FULL-BRAIN accuracy if cutover were lowered:"
[0.40, 0.50, 0.60, 0.70].each do |thr|
  rescued = rescue_data.count { |d| d[:mapped_label] && d[:mapped_label] == d[:expected] && d[:conf] >= thr }
  acc = pct(regex_hits + rescued, main_total)
  puts format('      cutover %.2f -> %.2f%%   (regex %d + rescued %d)', thr, acc, regex_hits, rescued)
end

# 4. PER-INTENT (worst first, min 20 sample rows)
puts "\n[4] PER-INTENT TRUE ACCURACY (>=20 sampled rows, worst first)"
puts format('  %-26s %6s %6s %8s', 'real_intent', 'total', 'hits', 'acc%')
per_intent.select { |_, s| s[:total] >= 20 }
          .sort_by { |_, s| pct(s[:hits], s[:total]) }
          .each do |real, s|
  puts format('  %-26s %6d %6d %7.1f%%', real, s[:total], s[:hits], pct(s[:hits], s[:total]))
end

# 5. SAMPLES — genuinely-unhandled (regex missed AND brain final wrong), 3 worst intents
puts "\n[5] GENUINELY-UNHANDLED SAMPLES (regex miss + brain wrong) — 3 worst intents"
worst3 = per_intent.select { |_, s| s[:total] >= 20 }
                   .sort_by { |_, s| pct(s[:hits], s[:total]) }
                   .first(3)
worst3.each do |real, s|
  puts "\n  ── #{real}  (#{pct(s[:hits], s[:total]).round(1)}%, expected=#{EXPECTED_MAP[real]})"
  samples[real].first(5).each do |ex|
    puts format('     final=%-22s rag=%s@%s | %s', ex[:final], ex[:rag_label] || '-', ex[:rag_conf] || '-', ex[:text])
  end
end

# + UNMAPPED-TRUTH bucket (informational)
puts "\n[+] UNMAPPED-TRUTH (greeting_chitchat / unclear) — informational, not in accuracy"
unmapped.sort_by { |_, u| -u[:total] }.each do |real, u|
  top = u[:final].sort_by { |_, c| -c }.first(4).map { |sym, c| "#{sym}×#{c}" }.join(', ')
  puts "  #{real}: total=#{u[:total]}  brain final: #{top}"
end

puts "\n#{line}\n[realbrain] done in #{elapsed.round(1)}s, #{@embed_calls} embedding calls.\n#{line}"
