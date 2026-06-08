# frozen_string_literal: true

# ─────────────────────────────────────────────────────────────────────────────
# INTENT REGRESSION — proves the balance_check + payment tag-request patterns catch
# the real misses WITHOUT stealing from intents that already work.
#
#   RUN (Render Shell):  bundle exec rails runner script/patra_intent_regression.rb
#
# READ-ONLY: only calls Games::IntentDetector.detect (pure regex, no network) and
# optionally reads bella_rag_pairs for a real-data sample. No writes, no Telegram.
#
# PASS only if: every REGRESSION invariant holds at 100% (loads still :load, clean
# picks still :payment_method_chosen, cashouts not stolen, "...cashapp?" still blocked,
# stand-downs not picked) AND the two NEW categories clear their catch-rate floors.
# ─────────────────────────────────────────────────────────────────────────────

Rails.logger.level = Logger::ERROR

def d(text)
  r = Games::IntentDetector.detect(text)
  r.is_a?(Hash) ? r[:intent] : nil
end

# category => { cases: [...], check: ->(actual){bool}, floor: % (nil = must be 100) }
SUITE = {
  'NEW_BALANCE (=> :balance_check)' => {
    floor: 80,
    check: ->(a) { a == :balance_check },
    cases: [
      'i have 22 on there', '5 dollars on gamevault', 'only 22 on there',
      'i still have 30 on juwa', 'nothing on there', '0 balance',
      "what's my max", 'only .21 cents', 'theres 15 left on gv',
      'almost a dollar on there', 'how much is my cashout', 'no money left'
    ]
  },
  'NEW_PAYMENT (=> :payment_method_chosen)' => {
    floor: 75,
    check: ->(a) { a == :payment_method_chosen },
    cases: [
      'chime tag pls', 'cash tag', 'cash tag sweetie', 'cashapp handle',
      'PayPal?', 'Chime?', 'do you have apple pay', 'do u take cashapp',
      'venmo handle', 'zelle info'
    ]
  },
  'LOADS_KEEP (=> :load) [regression]' => {
    floor: nil,
    check: ->(a) { a == :load },
    cases: [
      'load 20 on juwa', 'add 20', 'put 5 on gv', 'recharge 50',
      'load me up', 'top up 30', 'load 22 on juwa', 'load 100 fire kirin'
    ]
  },
  'PICKS_KEEP (=> :payment_method_chosen) [regression]' => {
    floor: nil,
    check: ->(a) { a == :payment_method_chosen },
    cases: [
      'cashapp', 'send your chime', "i'll use paypal", 'pay with venmo', "let's do zelle"
    ]
  },
  'CASHOUT_KEEP (=> :cashout) [regression]' => {
    floor: nil,
    check: ->(a) { a == :cashout },
    cases: ['cash out 50', 'i want to cashout', 'redeem 100', 'withdraw 20']
  },
  'BLOCKED_Q (must NOT be a pick) [regression]' => {
    floor: nil,
    check: ->(a) { a != :payment_method_chosen },
    cases: ['you only have cashapp?', 'do you only take cashapp?', 'is paypal the only option?']
  },
  'STANDDOWNS (must NOT be a pick) [regression]' => {
    floor: nil,
    check: ->(a) { a != :payment_method_chosen },
    cases: [
      'who do i send request to', 'now who do i send request to for the 20',
      'request 10 venmo', '$llacie-dagenhart-2', '+brittney-curnett-2.venmo',
      'where do i deposit', 'how u load money'
    ]
  }
}.freeze

puts '=' * 78
puts 'INTENT REGRESSION SUITE'
puts '=' * 78

overall_pass = true
SUITE.each do |name, spec|
  total = spec[:cases].size
  passes = 0
  fails = []
  spec[:cases].each do |text|
    actual = d(text)
    if spec[:check].call(actual)
      passes += 1
    else
      fails << [text, actual]
    end
  end
  rate = (passes.to_f / total * 100).round(1)
  regression = spec[:floor].nil?
  ok = regression ? (passes == total) : (rate >= spec[:floor])
  overall_pass &&= ok
  puts "\n[#{ok ? 'PASS' : 'FAIL'}] #{name}  #{passes}/#{total} (#{rate}%)#{regression ? '  [invariant: must be 100%]' : "  [floor #{spec[:floor]}%]"}"
  fails.each { |t, a| puts "    MISS: #{a.inspect.ljust(26)} <- #{t}" }
end

# ── OPTIONAL real-data sample (informational; rescue-guarded so it never blocks) ──
puts "\n#{'-' * 78}\nREAL-DATA SAMPLE (informational — regex accuracy on live rows)"
begin
  expected_map = Games::ConversationOrchestrator::RAG_TO_INTENT_MAP
  watch = %w[balance_check payment_handle_request load_deposit cashout_redeem
             load_freeplay status_check payment_sent_confirmation]
  watch.each do |real|
    exp = expected_map[real]
    next puts("  #{real}: (not in RAG map)") unless exp

    rows = BellaRagPair.where(account_id: 2, real_intent: real)
                       .order(Arel.sql('RANDOM()')).limit(300)
                       .pluck(:customer_text)
    next puts("  #{real}: no rows") if rows.empty?

    hits = rows.count { |t| d(t.to_s) == exp }
    puts format('  %-26s regex-acc %5.1f%%  (%d/%d, expected=%s)',
                real, hits.to_f / rows.size * 100, hits, rows.size, exp)
  end
rescue StandardError => e
  puts "  (real-data sample skipped: #{e.class}: #{e.message})"
end

puts "\n#{'=' * 78}"
puts overall_pass ? 'RESULT: PASS — new patterns catch more, no regression invariant broken.' \
                  : 'RESULT: FAIL — review the MISS lines above before deploying.'
puts '=' * 78
