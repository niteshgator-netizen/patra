# frozen_string_literal: true

# ─────────────────────────────────────────────────────────────────────────────
# PATRA CORPUS REPLAY GRADER — replay the REAL 73k-message customer corpus
# (bella_rag_pairs, READ-ONLY) against the deterministic brain, and grade it.
#
#   TIER 1 (always, zero LLM, zero sends, zero writes):
#     every row's customer_text -> Games::IntentDetector.detect (real code) ->
#     static orchestrator routing map. Grades: resolved vs fallthrough,
#     match vs the recorded real_intent label (labels are noisy - informational),
#     money-labeled row with ZERO detection = HIGH severity.
#
#   TIER 2 (only when DEEPSEEK_API_KEY present; REPLAY_LLM_SAMPLE rows,
#     default 500, stratified across labels, money-weighted x3):
#     full DeepSeek reply via the REAL Ai::ReplyService prompt build +
#     invoke_anthropic(use_deepseek: true), with panel/Telegram/approvals
#     STUBBED (replay-smoke pattern). Reply graders: <=2 lines, no bullets,
#     no banned filler, no AI admission, no CoT leak, NO configured
#     display_name (person name), every $/@ tag in the exact configured
#     display_handle set, no untraceable $ amount, money intent never
#     dead-ends, captured escalations carry the 5-part context.
#
#   RUN (Render Shell):
#     bundle exec rails runner script/patra_corpus_replay.rb
#   Options (ENV):
#     RESUME=1              resume Tier 1 from tmp/bp_corpus_checkpoint.json
#     TIER1_LIMIT=N         only first N rows (smoke-test the grader itself)
#     REPLAY_LLM_SAMPLE=N   Tier 2 sample size (default 500; 0 disables)
#     REPORT_PATH=path      report output (default PATRA_REPLAY_REPORT.md)
#
# SAFETY: bella_rag_pairs is READ-ONLY (pluck only, find_in_batches). Tier 1
# performs no writes at all and calls no network. Tier 2 stubs every send
# surface before any service call; the only real network is the DeepSeek API.
# ─────────────────────────────────────────────────────────────────────────────

require 'json'
require 'ostruct'
require 'set'

ACCOUNT_ID = 2
REPORT_PATH = ENV.fetch('REPORT_PATH', 'PATRA_REPLAY_REPORT.md')
CHECKPOINT = 'tmp/bp_corpus_checkpoint.json'
TIER1_LIMIT = ENV['TIER1_LIMIT'].to_i
LLM_SAMPLE = ENV.fetch('REPLAY_LLM_SAMPLE', '500').to_i

Rails.logger.level = :warn # detect() INFO-logs 2+ lines per call; 73k rows would swamp the log

# ── label maps (from the live 27-label distribution, 2026-06-11) ─────────────
# acceptable detector intents per recorded label. Labels are NOISY - a miss
# here is informational ("mismatch"), only zero-detection on a money label is
# graded HIGH.
ACCEPTABLE = {
  'load_deposit'             => %i[load load_freeplay load_bonus username_provided payment_sent_confirmation payment_method_chosen],
  'payment_handle_request'   => %i[payment_method_chosen payment_method_question list_platforms],
  'load_freeplay'            => %i[load_freeplay load],
  'greeting_chitchat'        => [],
  'cashout_redeem'           => %i[cashout redeem_partial_replay],
  'status_check'             => %i[status_check],
  'payment_sent_confirmation' => %i[payment_sent_confirmation status_check load],
  'complaint_angry'          => %i[complaint_angry],
  'tech_issue'               => %i[tech_issue reset_password],
  'new_account_other_game'   => %i[request_account_creation request_multi_account_creation new_account_reissue],
  'redeem_partial_replay'    => %i[redeem_partial_replay cashout],
  'referral'                 => %i[referral],
  'reset_password'           => %i[reset_password],
  'whats_hitting'            => %i[whats_hitting],
  'new_account_reissue'      => %i[new_account_reissue request_account_creation],
  'load_bonus'               => %i[load_bonus load],
  'transfer_between_games'   => %i[transfer_between_games],
  'balance_check'            => %i[balance_check replay_from_balance],
  'unclear'                  => [],
  'replay_from_balance'      => %i[replay_from_balance balance_check],
  'new_account_new_player'   => %i[request_account_creation request_multi_account_creation],
  'list_platforms'           => %i[list_platforms payment_method_question],
  'request_download_link'    => %i[request_download_link request_app_link request_game_link],
  'cashout_rules'            => %i[cashout_rules],
  'request_game_link'        => %i[request_game_link request_download_link request_app_link],
  'payment_method_question'  => %i[payment_method_question payment_method_chosen list_platforms],
  'request_app_link'         => %i[request_app_link request_download_link request_game_link]
}.freeze

# labels where money is at stake: zero detection = HIGH severity miss.
MONEY_LABELS = %w[
  load_deposit load_freeplay load_bonus cashout_redeem payment_sent_confirmation
  payment_handle_request redeem_partial_replay transfer_between_games
  replay_from_balance balance_check status_check referral
].freeze

# labels where fallthrough to the LLM is the DESIGNED outcome.
FALLTHROUGH_OK = %w[greeting_chitchat unclear].freeze

# intent -> orchestrator handler (static routing map, mirrors the case at
# conversation_orchestrator.rb:275-328).
HANDLER = {
  load_freeplay: 'handle_load_freeplay', load_bonus: 'handle_load_bonus',
  load: 'handle_load_intent', cashout: 'handle_cashout_intent',
  username_provided: 'handle_username_provided',
  request_account_creation: 'handle_account_creation_request',
  request_multi_account_creation: 'handle_multi_account_creation_request',
  payment_method_chosen: 'handle_payment_method_chosen',
  reset_password: 'handle_reset_password_intent',
  payment_sent_confirmation: 'handle_payment_sent_confirmation',
  status_check: 'handle_status_check', complaint_angry: 'handle_complaint_angry',
  tech_issue: 'handle_tech_issue', balance_check: 'handle_balance_check',
  transfer_between_games: 'handle_transfer_between_games',
  whats_hitting: 'handle_whats_hitting', referral: 'handle_referral',
  redeem_partial_replay: 'handle_redeem_partial_replay',
  new_account_reissue: 'handle_new_account_reissue',
  replay_from_balance: 'handle_replay_from_balance',
  request_game_link: 'handle_request_game_link',
  request_download_link: 'handle_request_download_link',
  request_app_link: 'handle_request_app_link',
  cashout_rules: 'handle_cashout_rules', list_platforms: 'handle_list_platforms',
  payment_method_question: 'handle_payment_method_question'
}.freeze

# ── bp5 P6 grader calibration helpers (precision UP, strictness NEVER down) ──

# unknown-tag: only letter-bearing $/@ tokens are tag candidates (a bare
# "$10"/"$12" is an AMOUNT, not a tag — was a false positive). Allowed set =
# exact configured display_handles PLUS sigil-prefixed echoes of handles that
# are configured WITHOUT a sigil (PayPal usernames have no $/@ — the model
# writing "$devpatel742" for configured "devpatel742" is still OUR handle).
# Sigil-bearing configured handles still require an EXACT match (no loosening).
def grade_unknown_tags(reply, customer_text, exact_tags, prefixless_tags)
  reply.scan(/[\$@][a-z0-9][a-z0-9._\-]*/i).map(&:downcase)
       .select { |tg| tg.match?(/[a-z]/) }
       .reject { |tg| exact_tags.include?(tg) }
       .reject { |tg| prefixless_tags.include?(tg.sub(/\A[\$@]/, '')) }
       .reject { |tg| customer_text.to_s.downcase.include?(tg.sub(/\A[\$@]/, '')) }
end

# untraceable-amount: a $ amount is traceable when it appears verbatim in
# input+prompt OR is single-step arithmetic with the RIGHT shape: a
# %-adjacent percent applied to a $-adjacent amount (30% of $20 = 6, or the
# 26 total), or a sum/difference of two $-adjacent amounts. Operands are NOT
# free numbers (reviewer: unconstrained pairs whitelisted ~every value under
# $100 at realistic prompt density — iron-rule violation, fixed).
def derive_allowed_amounts(customer_text, sys)
  src = "#{customer_text} #{sys}"
  raw = src.scan(/\d+(?:\.\d+)?/)
  percents = src.scan(/(\d+(?:\.\d+)?)\s*%/).flatten.map(&:to_f).uniq.first(20)
  dollars = src.scan(/\$\s*(\d+(?:\.\d+)?)/).flatten.map(&:to_f).uniq.first(40)
  derived = Set.new
  dollars.each do |a|
    percents.each do |p|
      derived << (a * p / 100.0).round(2)
      derived << (a * (1 + p / 100.0)).round(2)
    end
    dollars.each do |b|
      derived << (a + b).round(2)
      derived << (a - b).round(2) if a > b
    end
  end
  [Set.new(raw), derived]
end

def amount_traceable?(num_str, raw_set, derived_set)
  return true if raw_set.include?(num_str)

  f = num_str.to_f
  derived_set.any? { |d| (d - f).abs < 0.001 }
end

# money-dead-end: a money-labeled turn that is PURE gratitude/closing needs no
# action language (labels are noisy — "thanks" rows carry load_deposit), and a
# reply that DELIVERED a configured handle IS the action. Markdown-list
# replies still fail via the separate bullets-or-markdown check (untouched).
GRATITUDE_CLOSING = /\A(?:ok |okay )?(?:thanks|thank you|thx|ty|tysm|you'?re welcome|welcome|bye|good ?night|gn|np|no problem)(?: (?:so much|alot|a lot|love|hun|dear|bella))*\z/

def gratitude_closing_turn?(customer_text)
  # a digit or $ in the raw turn means a possible amount/ask — never exempt
  return false if customer_text.to_s.match?(/[\d$]/)

  core = customer_text.to_s.downcase.gsub(/['’]/, "'").gsub(/[^a-z\s']/, ' ').gsub(/\s+/, ' ').strip
  return false if core.empty?

  core.match?(GRATITUDE_CLOSING)
end

# it6 A5: DeepSeek (Tier-2) calls retry up to 3x with exponential backoff on transient network errors
# so a momentary blip records a real grade instead of a skip. Persistent failures still raise → the
# caller's rescue records the (now rare) skip. Drives network-skip toward 0.
def invoke_with_retry(svc, framed, sys, tries: 3)
  attempt = 0
  begin
    attempt += 1
    svc.send(:invoke_anthropic, framed, sys, use_deepseek: true)
  rescue Net::OpenTimeout, Net::ReadTimeout, Timeout::Error, Errno::ECONNRESET, SocketError
    if attempt < tries
      sleep(0.5 * (2**(attempt - 1)))
      retry
    end
    raise
  end
end

def normalize_cluster(text)
  t = text.to_s.downcase
  t = t.gsub(/[\$@][a-z0-9][a-z0-9._\-]*/, '$TAG')
  t = t.gsub(/\d+(?:\.\d+)?/, '#')
  t = t.gsub(/[^a-z#$?\s']/, ' ')
  t.gsub(/\s+/, ' ').strip[0, 80]
end

# ── TIER 1 ────────────────────────────────────────────────────────────────────
def blank_tally
  {
    'rows' => 0, 'resolved' => 0, 'matched' => 0, 'mismatched' => 0,
    'fallthrough' => 0, 'money_miss' => 0, 'errors' => 0
  }
end

state = {
  'last_id' => 0, 'processed' => 0,
  'per_label' => Hash.new { |h, k| h[k] = blank_tally },
  'clusters' => {} # norm => {'count','label_counts','examples'[5],'grader'}
}
if ENV['RESUME'] == '1' && File.exist?(CHECKPOINT)
  raw = JSON.parse(File.read(CHECKPOINT))
  state['last_id'] = raw['last_id'].to_i
  state['processed'] = raw['processed'].to_i
  raw['per_label'].each { |k, v| state['per_label'][k] = blank_tally.merge(v) }
  state['clusters'] = raw['clusters'] || {}
  puts "[tier1] RESUMED from id=#{state['last_id']} processed=#{state['processed']}"
end

def checkpoint!(state)
  File.write("#{CHECKPOINT}.tmp", JSON.generate(state))
  File.rename("#{CHECKPOINT}.tmp", CHECKPOINT)
end

puts "\n#{'=' * 72}\nPATRA CORPUS REPLAY — TIER 1 (deterministic, zero LLM, READ-ONLY)\n#{'=' * 72}"
t0 = Time.now
scope = BellaRagPair.where(account_id: ACCOUNT_ID).where('id > ?', state['last_id']).order(:id)
batch_no = 0
done = false
scope.in_batches(of: 2000) do |batch|
  break if done

  rows = batch.pluck(:id, :customer_text, :real_intent)
  rows.each do |(id, text, label)|
    break (done = true) if TIER1_LIMIT.positive? && state['processed'] >= TIER1_LIMIT

    label = label.to_s
    t = state['per_label'][label]
    t['rows'] += 1
    state['processed'] += 1
    state['last_id'] = id

    intent = begin
      r = Games::IntentDetector.detect(text.to_s)
      r.is_a?(Hash) ? r[:intent] : nil
    rescue StandardError
      t['errors'] += 1
      nil
    end

    if intent
      t['resolved'] += 1
      if (acc = ACCEPTABLE[label]) && acc.any?
        acc.include?(intent) ? t['matched'] += 1 : t['mismatched'] += 1
      end
    else
      t['fallthrough'] += 1
      # it6 A5 calibration: a PURE gratitude/closing turn mislabeled with a money label is GRADER
      # NOISE, not a detector gap — routing it to money would violate R2 (gratitude stays chitchat).
      # gratitude_closing_turn? already excludes any turn carrying a digit/$ (a real ask).
      money_miss = MONEY_LABELS.include?(label) && !gratitude_closing_turn?(text)
      t['money_miss'] += 1 if money_miss
      unless FALLTHROUGH_OK.include?(label)
        key = normalize_cluster(text)
        c = state['clusters'][key] ||= { 'count' => 0, 'label_counts' => {}, 'examples' => [], 'grader' => 'fallthrough' }
        c['count'] += 1
        c['label_counts'][label] = c['label_counts'].fetch(label, 0) + 1
        c['examples'] << text.to_s[0, 160] if c['examples'].size < 5
        c['grader'] = 'money-miss(HIGH)' if money_miss
      end
    end
  end
  batch_no += 1
  checkpoint!(state) if (batch_no % 5).zero?
  puts "[tier1] #{state['processed']} rows (#{(state['processed'] / (Time.now - t0)).round}/s)"
end
checkpoint!(state)
puts "[tier1] DONE: #{state['processed']} rows in #{(Time.now - t0).round}s"

# ── TIER 1 report assembly ────────────────────────────────────────────────────
totals = blank_tally
state['per_label'].each_value { |t| totals.keys.each { |k| totals[k] += t[k] } }

top_clusters = state['clusters'].sort_by { |_k, c| -c['count'] }.first(25)

report = +"# PATRA REPLAY REPORT\n\n"
report << "Generated: #{Time.current.iso8601} · account=#{ACCOUNT_ID} · rows graded: #{state['processed']}\n\n"
report << "## TIER 1 — deterministic routing (real IntentDetector, zero LLM)\n\n"
report << "HEADLINE: #{totals['rows']} rows · resolved #{totals['resolved']} " \
          "(#{(100.0 * totals['resolved'] / [totals['rows'], 1].max).round(1)}%) · " \
          "fallthrough #{totals['fallthrough']} · **money-label misses (HIGH): #{totals['money_miss']}** · " \
          "label-mismatch (informational, labels noisy): #{totals['mismatched']} · detect errors: #{totals['errors']}\n\n"
report << "| real_intent | rows | resolved | matched | mismatch | fallthrough | money-miss |\n"
report << "|---|---|---|---|---|---|---|\n"
state['per_label'].sort_by { |_l, t| -t['rows'] }.each do |label, t|
  report << "| #{label.empty? ? '(blank)' : label} | #{t['rows']} | #{t['resolved']} | #{t['matched']} | " \
            "#{t['mismatched']} | #{t['fallthrough']} | #{t['money_miss']} |\n"
end
report << "\n(fallthrough on greeting_chitchat/unclear is the designed outcome — excluded from clusters)\n"

report << "\n## TOP 25 FALLTHROUGH CLUSTERS\n\n"
top_clusters.each_with_index do |(key, c), i|
  main_label = c['label_counts'].max_by { |_l, n| n }&.first.to_s
  acc = ACCEPTABLE[main_label] || []
  suspected = acc.any? ? (HANDLER[acc.first] || 'LLM') : 'LLM (DeepSeek persona)'
  report << "### #{i + 1}. (#{c['count']}x) `#{key}`\n"
  report << "- failing grader: #{c['grader']} · top label: #{main_label} · suspected handler: #{suspected}\n"
  c['examples'].each { |ex| report << "  - #{ex.inspect}\n" }
  report << "\n"
end

# ── TIER 2 ────────────────────────────────────────────────────────────────────
tier2_summary = nil
if LLM_SAMPLE.positive? && ENV['DEEPSEEK_API_KEY'].to_s.empty?
  tier2_summary = "## TIER 2 — SKIPPED: DEEPSEEK_API_KEY not set in this environment.\n" \
                  "Run on Render worker shell: `REPLAY_LLM_SAMPLE=#{LLM_SAMPLE} bundle exec rails runner script/patra_corpus_replay.rb`\n"
  puts '[tier2] SKIPPED - no DEEPSEEK_API_KEY'
elsif LLM_SAMPLE.positive?
  puts "\n#{'=' * 72}\nTIER 2 — DeepSeek reply grading (sample #{LLM_SAMPLE}, stubs installed)\n#{'=' * 72}"

  # stubs (replay-smoke pattern) — restored in ensure
  $orig = {}
  def stub_singleton(mod, name, &impl)
    $orig[[mod, name]] ||= (mod.respond_to?(name) ? mod.method(name) : nil)
    mod.define_singleton_method(name, &impl)
  end

  class CorpusFakeClient
    def method_missing(*) = { 'code' => 0, 'data' => { 'user_id' => 1, 'user_balance' => 50.0, 'agent_balance' => 100_000 } }
    def respond_to_missing?(*) = true
  end
  $TG = []
  stub_singleton(Games::ClientRegistry, :client_for) { |_ag| CorpusFakeClient.new }
  %i[human_escalation load_failed load_alert cashout_alert cashout_failed api_error
     low_balance_alert payment_pending_alert secret_phrase_triggered send_raw
     send_to_cashout_group winback_manual_alert].each do |m|
    stub_singleton(Games::TelegramNotifier, m) { |*_a, **k| $TG << [m, k]; { ok: true } }
  end
  if defined?(Approvals::CashoutApprovalGate)
    stub_singleton(Approvals::CashoutApprovalGate, :create_request!) { |**_k| OpenStruct.new(id: 'CORPUS') }
  end
  $LAST_POST = nil
  stub_singleton(HTTParty, :post) do |*args, **kw|
    resp = $orig[[HTTParty, :post]].call(*args, **kw)
    $LAST_POST = resp
    resp
  end

  account = Account.find(ACCOUNT_ID)
  handles = account.payment_handles.to_a
  display_names = handles.map { |h| h.try(:display_name).to_s.strip }.select { |n| n.length >= 5 }
  exact_tags = handles.map { |h| h.respond_to?(:display_handle) ? h.display_handle.to_s : '' }
                      .reject(&:empty?).map(&:downcase)
  # bp5 P6: handles configured WITHOUT a $/@ sigil (e.g. PayPal usernames)
  prefixless_tags = exact_tags.reject { |t| t.start_with?('$', '@') }

  inbox = account.inboxes.detect { |i| i.channel_type == 'Channel::Api' } || account.inboxes.order(:id).first
  abort '[tier2] no inbox' unless inbox
  contact = Contact.create!(account: account, name: 'CORPUS_REPLAY_CONTACT')
  ci = ContactInbox.create!(contact: contact, inbox: inbox, source_id: SecureRandom.uuid)
  conv = Conversation.create!(account: account, inbox: inbox, contact: contact, contact_inbox: ci)

  begin
    # stratified, money-weighted sample
    labels = BellaRagPair.where(account_id: ACCOUNT_ID).where.not(real_intent: [nil, '']).distinct.pluck(:real_intent)
    weights = labels.to_h { |l| [l, MONEY_LABELS.include?(l) ? 3.0 : 1.0] }
    wsum = weights.values.sum
    plan = labels.to_h { |l| [l, [(LLM_SAMPLE * weights[l] / wsum).round, 3].max] }
    samples = plan.flat_map do |l, n|
      BellaRagPair.where(account_id: ACCOUNT_ID, real_intent: l)
                  .where('length(trim(customer_text)) >= 3')
                  .order(Arel.sql('RANDOM()')).limit(n).pluck(:customer_text).map { |t| [l, t] }
    end.first(LLM_SAMPLE)
    puts "[tier2] sampled #{samples.size} rows across #{labels.size} labels"

    t2 = Hash.new { |h, k| h[k] = { pass: 0, fail: 0, skip: 0 } }
    t2_failures = []

    samples.each_with_index do |(label, text), idx|
      svc = Ai::ReplyService.new(conv.display_id, account_id: ACCOUNT_ID)
      def svc.store_player_username(_cid); nil; end
      def svc.clear_game_username(_cid); nil; end
      begin
        framed = [{ 'role' => 'user', 'content' => text.to_s }]
        rag_block = (svc.send(:retrieve_rag_examples_block, text) rescue '')
        svc.instance_variable_set(:@rag_examples, (svc.send(:fetch_rag_examples, text, ACCOUNT_ID) rescue []))
        svc.instance_variable_set(:@reply_pref, (ReplyPreference.for_account(ACCOUNT_ID) rescue nil))
        sys = svc.send(:build_system_prompt,
                       (svc.send(:fetch_payment_info) rescue ''), (svc.send(:fetch_ai_training) rescue ''),
                       (svc.send(:fetch_ai_persona) rescue ''), (svc.send(:fetch_player_profile) rescue ''),
                       (svc.send(:fetch_all_canned_responses) rescue ''),
                       (svc.send(:needs_payment_link?, framed) rescue false), rag_examples_block: rag_block)
        $LAST_POST = nil
        $TG.clear
        reply = invoke_with_retry(svc, framed, sys)
        raw = ($LAST_POST&.parsed_response rescue nil)
        ct_len = raw.is_a?(Hash) ? raw.dig('choices', 0, 'message', 'content').to_s.strip.length : 0

        if reply.to_s.strip.empty?
          t2[label][:skip] += 1
          print 's'
          next
        end

        v = []
        lines = reply.split(/\r?\n/).reject { |l| l.strip.empty? }
        v << 'over-2-lines' if lines.size > 2
        v << 'bullets-or-markdown' if lines.any? { |l| l.match?(/^\s*([-*•]|\d+[.)])\s/) } || reply.match?(/\*\*|```/)
        v << 'banned-phrase' if reply.match?(/certainly!?|great question/i)
        v << 'ai-admission' if reply.downcase.match?(/as an ai|language model|i am an ai|i'm an ai|\bai (assistant|model|bot)\b|i am a bot|i'm a bot/)
        cot = Ai::ReplyService::COT_MARKERS.select { |re| reply.match?(re) }
        v << "cot-marker(#{cot.size})" if cot.any?
        v << "cot-leak(#{reply.strip.length}/#{ct_len})" if ct_len.positive? && reply.strip.length > ct_len + 8
        v << 'person-name-leak' if display_names.any? { |n| reply.downcase.include?(n.downcase) }
        # bp5 P6 calibrated graders (see helper defs at top; precision UP only)
        bad_tags = grade_unknown_tags(reply, text, exact_tags, prefixless_tags)
        v << "unknown-tag(#{bad_tags.join(',')})" if bad_tags.any?
        raw_nums, derived_nums = derive_allowed_amounts(text, sys)
        stray = reply.scan(/\$\s*(\d+(?:\.\d+)?)/).flatten.reject { |n| amount_traceable?(n, raw_nums, derived_nums) }
        v << "untraceable-amount(#{stray.join(',')})" if stray.any?
        if MONEY_LABELS.include?(label)
          act = reply.match?(/\?|send|screenshot|tag|load|process|confirm|check|teammate|manager|one sec|moment|hang tight/i)
          # delivering OUR handle is the action for deposit-direction labels
          # only — a cashout needs THEIR tag, so a tag-only reply stays a dead
          # end there (reviewer finding b)
          unless %w[cashout_redeem redeem_partial_replay].include?(label)
            act ||= exact_tags.any? { |tg| reply.downcase.include?(tg) }
          end
          v << 'money-dead-end' unless act || gratitude_closing_turn?(text)
        end
        five_part_bad = $TG.select { |(m, k)| m == :human_escalation }
                           .reject { |(_m, k)| k[:reason].to_s.include?('PLAYER WANTS') }
        v << 'escalation-not-5-part' if five_part_bad.any?

        if v.empty?
          t2[label][:pass] += 1
          print '.'
        else
          t2[label][:fail] += 1
          print 'F'
          t2_failures << { label: label, msg: text.to_s[0, 120], reply: reply[0, 200], v: v }
        end
      rescue Net::OpenTimeout, Net::ReadTimeout, Timeout::Error, Errno::ECONNRESET, SocketError
        t2[label][:skip] += 1
        print 's'
      rescue StandardError => e
        t2[label][:fail] += 1
        print 'E'
        t2_failures << { label: label, msg: text.to_s[0, 120], reply: "<EXC #{e.class}: #{e.message[0, 120]}>", v: ['exception'] }
      end
    end

    tp = t2.values.sum { |x| x[:pass] }; tf = t2.values.sum { |x| x[:fail] }; ts = t2.values.sum { |x| x[:skip] }
    tier2_summary = +"## TIER 2 — DeepSeek reply grading\n\n"
    tier2_summary << "HEADLINE: #{tp} pass / #{tf} fail / #{ts} skip (network noise) of #{samples.size} sampled\n\n"
    tier2_summary << "| label | pass | fail | skip |\n|---|---|---|---|\n"
    t2.sort.each { |l, x| tier2_summary << "| #{l} | #{x[:pass]} | #{x[:fail]} | #{x[:skip]} |\n" }
    if t2_failures.any?
      tier2_summary << "\n### Tier 2 failures (first 200, verbatim)\n"
      t2_failures.first(200).each do |f|
        tier2_summary << "- [#{f[:label]}] #{f[:v].join(', ')}\n  - PLAYER: #{f[:msg].inspect}\n  - BELLA: #{f[:reply].inspect}\n"
      end
    end
    puts "\n[tier2] #{tp} pass / #{tf} fail / #{ts} skip"
  ensure
    begin
      Conversation.where(contact_id: contact.id).destroy_all
      contact.destroy
      puts '[tier2-cleanup] destroyed throwaway contact + conversation'
    rescue StandardError => e
      puts "[tier2-cleanup] failed: #{e.class}: #{e.message}"
    end
    $orig.each { |(mod, name), orig| mod.define_singleton_method(name, orig) if orig }
    puts "[tier2-cleanup] restored stubs · telegram recorded=#{$TG.size} (none sent)"
  end
end

report << "\n#{tier2_summary}" if tier2_summary
File.write(REPORT_PATH, report)
puts "\nREPORT -> #{REPORT_PATH}"
