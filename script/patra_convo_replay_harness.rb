# frozen_string_literal: true

# ─────────────────────────────────────────────────────────────────────────────
# PATRA CONVERSATION REPLAY HARNESS — replay the 2,057 downloaded REAL chats
# (JSON files) end-to-end through the REAL brain, each as a fresh synthetic
# customer, with the panel FAKED and every result graded.
#
# Each JSON file = one distinct customer. Only real CUSTOMER text turns are fed
# (agent/system/call/theme/attachment noise is filtered out and counted).
# Historical identities are swapped: the customer becomes TESTER_<n> with game
# username tester<n> (created via the real account-creation flow first), and
# any reply that copies a name/username/$ amount from the SOURCE chat is a
# HIGH violation (regression net for the Change-1 RAG-leak fix).
#
#   RUN (Render Shell — this script is RENDER-ONLY, agent_games credentials
#   are encrypted and only decrypt there):
#     PARSE_ONLY=1 bundle exec rails runner script/patra_convo_replay_harness.rb
#     bundle exec rails runner script/patra_convo_replay_harness.rb                  # MODE=route (all files, zero LLM)
#     MODE=execute THREADS=6 RESUME=1 bundle exec rails runner script/patra_convo_replay_harness.rb
#     MODE=full LIMIT=150 THREADS=6 RESUME=1 bundle exec rails runner script/patra_convo_replay_harness.rb
#     MODE=full LIMIT=3 TELEGRAM=live GATE=live bundle exec rails runner script/patra_convo_replay_harness.rb  # walkthrough
#
#   ENV:
#     MODE=route|execute|full  route: detector+routing stats only, zero LLM, zero writes.
#                              execute: real orchestrator handlers run (FakeClient panel),
#                                       turns the orchestrator doesn't handle are recorded, no DeepSeek.
#                              full: execute + real DeepSeek replies on unhandled turns.
#     LIMIT=N                  conversations to replay (0 = all; MODE=full defaults to 150, stratified)
#     THREADS=N                worker threads (default 1; 6-8 recommended; clamped to AR pool - 1)
#     TELEGRAM=fake|live       fake (default): record only. live: REALLY send, rate-limited
#                              (TG_RATE/min, hard cap TG_MAX then auto-degrade to record);
#                              live refuses >25 conversations unless FORCE_LIVE=1.
#     GATE=fake|live           live: real ApprovalRequest rows (walkthrough), cleaned up after.
#     AGENT_NAMES=a,b          force these sender names to the agent side of source chats
#     NO_PREAMBLE=1            don't auto-create the account first; grade that Bella asks instead
#     AUTOCONFIRM=1            (default) inject a synthetic "yes" when Bella asks "(yes/no)"
#     MAX_TURNS=N              cap customer turns per chat (default 60; overflow reported, never silent)
#     RESUME=1                 skip files already done per tmp/convo_replay_checkpoint.json
#     PARSE_ONLY=1             parse + classify + side-detection stats only, nothing replayed
#     DIR=path                 corpus dir (default test_corpus/messages_collected)
#     REPORT_PATH=path         report output (default PATRA_CONVO_REPLAY_REPORT.md)
#
# SAFETY: Games::ClientRegistry.client_for is stubbed to a per-thread FakeClient
# in EVERY replay mode — no real panel HTTP can happen, ever. Telegram and
# approvals are stubbed unless explicitly set live. referral_enabled is pinned
# false for the run (restored after). Every contact/conversation this script
# creates is labeled harness-test and destroyed in the ensure block; it never
# touches records it did not create. bella_rag_pairs is never written.
# ─────────────────────────────────────────────────────────────────────────────

require 'json'
require 'ostruct'
require 'set'

ACCOUNT_ID = 2
MODE = ENV.fetch('MODE', 'route')
DIR = ENV.fetch('DIR', 'test_corpus/messages_collected')
REPORT_PATH = ENV.fetch('REPORT_PATH', 'PATRA_CONVO_REPLAY_REPORT.md')
RESULTS_PATH = 'tmp/convo_replay_results.jsonl'
CHECKPOINT = 'tmp/convo_replay_checkpoint.json'
FLOWS_CACHE = 'tmp/convo_replay_flows.json'
LIMIT_ENV = ENV['LIMIT'].to_i
TELEGRAM = ENV.fetch('TELEGRAM', 'fake')
TG_RATE = [ENV.fetch('TG_RATE', '15').to_i, 1].max
TG_MAX = ENV.fetch('TG_MAX', '100').to_i
GATE = ENV.fetch('GATE', 'fake')
AGENT_NAMES = ENV.fetch('AGENT_NAMES', '').split(',').map { |s| s.strip.downcase }.reject(&:empty?)
NO_PREAMBLE = ENV['NO_PREAMBLE'] == '1'
AUTOCONFIRM = ENV.fetch('AUTOCONFIRM', '1') == '1'
MAX_TURNS = [ENV.fetch('MAX_TURNS', '60').to_i, 1].max
RESUME = ENV['RESUME'] == '1'
PARSE_ONLY = ENV['PARSE_ONLY'] == '1'

TEST_USERNAME = ENV.fetch('TEST_USERNAME', 'testuser1')
PERSONA_NAME = ENV.fetch('PERSONA_NAME', 'Bella') # historical agent names in customer turns become this
# known OLD agent names a customer might greet by name ("hi Shirley") even when
# that name isn't the sender — always swapped to PERSONA_NAME. Add more via ENV.
PERSONA_ALIASES = ENV.fetch('PERSONA_ALIASES', 'shirley').split(',').map { |s| s.strip.downcase }.reject(&:empty?)
abort "[harness] unknown MODE=#{MODE} (route|execute|full|export)" unless %w[route execute full export].include?(MODE)
abort "[harness] corpus dir not found: #{DIR} — commit the JSON folder first (see report/DUMP)" unless Dir.exist?(DIR)
if MODE == 'full' && ENV['DEEPSEEK_API_KEY'].to_s.strip.empty?
  abort '[harness] MODE=full needs DEEPSEEK_API_KEY (run on the Render worker shell)'
end

Rails.logger.level = :warn

# ── shared token rules (mirror of the Change-1 RAG-leak guard) ───────────────
STOPWORDS = Set.new(%w[
  bella shirley cashapp cash venmo paypal chime zelle varo boltpay apple google visa mastercard
  juwa juwa2 game games vault vegas sweeps ultra panda milky way fire kirin
  master orion stars vblink mafia gameroom machine tester
  firekirin gamevault pandamaster milkyway orionstars vegassweeps ultrapanda
  mrallinone cashmachine facebook messenger
  monday tuesday wednesday thursday friday saturday sunday
  today tomorrow tonight morning night weekend
  just send sent what when where which your this that okay sure sorry once done
  thanks thank welcome please congrats good great nice cool love perfect
  loaded loading load cashout redeem bonus freeplay deposit account username
  password screenshot balance points play playing win winning withdraw minimum
  need give want make check wait ready money time name same best link
  hello there here have will from with then they their about gonna wanna lemme
  yeah alright right also should could would still after before
]).freeze

USERNAME_SHAPE = /\b[a-zA-Z][a-zA-Z._-]*\d[a-zA-Z0-9._-]*\b/
NAME_SHAPE = /\b([A-Z][a-z]{3,})\b/
DOLLAR_SHAPE = /\$\s*(\d[\d,]{0,8}(?:\.\d{1,2})?)/

# intent -> orchestrator handler (tripwire copy of the static routing map,
# same source as script/patra_corpus_replay.rb HANDLER).
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

MONEY_INTENTS = %i[load load_bonus load_freeplay cashout redeem_partial_replay
                   transfer_between_games replay_from_balance payment_sent_confirmation].freeze
CREATION_INTENTS = %i[request_account_creation request_multi_account_creation new_account_reissue].freeze

# ── corpus parser ─────────────────────────────────────────────────────────────
TEXT_KEYS = %w[content text message body msg snippet].freeze
SENDER_KEYS = %w[sender_name sender from name author role side user who].freeze
AGENT_ROLE_VALUES = %w[agent admin page cashier operator bot assistant business outgoing].freeze
CUSTOMER_ROLE_VALUES = %w[customer user client guest visitor player incoming].freeze
AGENT_NAME_HINT = /bella|shirley|cashier|support|page|team/i

NOISE_TEXT_PATTERNS = {
  'call' => /\b(missed (your |a )?(video |audio )?call|started (a |the )?(video |audio )?call|call ended|joined the (video )?call)\b/i,
  'theme-event' => /\b(changed the (theme|chat theme|group photo|group name)|set the (emoji|nickname)|named the (group|conversation)|set your nickname)\b/i,
  'reaction' => /\breacted\b.{0,30}\bto your message\b/i,
  'unsent' => /\b(unsent a message|message is no longer available|removed a message)\b/i,
  'poll' => /\bcreated a poll\b/i,
  'email-noise' => /\b(view this email in your browser|unsubscribe|all rights reserved|no-?reply@)\b/i
}.freeze
ATTACHMENT_KEYS = %w[photos sticker audio_files gifs videos files share].freeze

def dig_text(h)
  TEXT_KEYS.each do |k|
    v = h[k]
    return v if v.is_a?(String) && !v.strip.empty?
  end
  nil
end

def dig_sender(h)
  SENDER_KEYS.each do |k|
    v = h[k]
    v = v['name'] || v['id'] || v['username'] if v.is_a?(Hash)
    return v.to_s if v.is_a?(String) && !v.strip.empty?
  end
  nil
end

def message_array?(node)
  return false unless node.is_a?(Array) && node.any?
  hashes = node.select { |e| e.is_a?(Hash) }
  return false if hashes.empty?
  with_shape = hashes.count { |e| dig_text(e) || ATTACHMENT_KEYS.any? { |k| e.key?(k) } }
  with_shape >= [hashes.size / 2, 1].max && hashes.any? { |e| dig_sender(e) }
end

def find_message_array(node, depth = 0)
  return node if message_array?(node)
  return nil if depth > 2
  case node
  when Hash then node.each_value { |v| (f = find_message_array(v, depth + 1)) and return f }
  when Array then node.each { |v| (f = find_message_array(v, depth + 1)) and return f }
  end
  nil
end

def turn_timestamp(h)
  %w[timestamp_ms timestamp ts created_at date time].each do |k|
    v = h[k]
    next if v.nil?
    return v.to_i if v.is_a?(Numeric) || v.to_s.match?(/\A\d{9,}\z/)
    begin
      return Time.zone.parse(v.to_s).to_i * 1000
    rescue StandardError
      next
    end
  end
  nil
end

def noise_category(h, text)
  return 'call' if h.key?('call_duration')
  return 'unsent' if h['is_unsent'] == true
  if text.to_s.strip.empty?
    return 'attachment' if ATTACHMENT_KEYS.any? { |k| h.key?(k) }
    return 'empty'
  end
  NOISE_TEXT_PATTERNS.each { |cat, re| return cat if text.match?(re) }
  nil
end

# Pass 1: raw-parse a file into normalized turns (no side assignment yet).
def parse_file(path)
  raw = JSON.parse(File.read(path, encoding: 'UTF-8'))
  arr = find_message_array(raw)
  return { error: 'no-message-array' } unless arr

  turns = []
  filtered = Hash.new(0)
  arr.each do |e|
    next unless e.is_a?(Hash)
    text = dig_text(e)
    if (cat = noise_category(e, text))
      filtered[cat] += 1
      next
    end
    turns << { who: dig_sender(e).to_s, text: text.to_s.strip, ts: turn_timestamp(e) }
  end
  return { error: 'no-text-turns', filtered: filtered } if turns.empty?

  turns.sort_by! { |t| t[:ts] || 0 } if turns.any? { |t| t[:ts] }
  # FB exports are usually newest-first when timestamps exist; sort_by above
  # normalizes. Without timestamps we keep file order.
  { turns: turns, filtered: filtered, senders: turns.map { |t| t[:who] }.reject(&:empty?).uniq }
rescue JSON::ParserError => e
  { error: "json-parse: #{e.message[0, 80]}" }
rescue StandardError => e
  { error: "#{e.class}: #{e.message[0, 80]}" }
end

# Pass 2: decide which sender is the agent for one file.
def agent_side?(who, frequent_agents)
  w = who.to_s.strip.downcase
  return true if AGENT_ROLE_VALUES.include?(w)
  return false if CUSTOMER_ROLE_VALUES.include?(w)
  return true if AGENT_NAMES.include?(w)
  return true if frequent_agents.include?(w)
  return true if w.match?(AGENT_NAME_HINT)
  nil # unknown
end

def mine_source_tokens(all_text, sender_names)
  names = Set.new
  usernames = Set.new
  amounts = Set.new
  all_text.scan(DOLLAR_SHAPE).flatten.each { |a| amounts << a.delete(',').to_f }
  all_text.scan(/\b(\d[\d,]{0,8}(?:\.\d{1,2})?)\s*(?:dollars?|bucks)\b/i).flatten.each { |a| amounts << a.delete(',').to_f }
  all_text.scan(USERNAME_SHAPE).each do |u|
    usernames << u.downcase if u.length >= 5 && !STOPWORDS.include?(u.downcase)
  end
  all_text.scan(NAME_SHAPE).flatten.each do |w|
    names << w.downcase unless STOPWORDS.include?(w.downcase)
  end
  sender_names.each do |sn|
    sn.to_s.split(/\s+/).each { |tok| names << tok.downcase if tok.length >= 3 && !STOPWORDS.include?(tok.downcase) }
  end
  { names: names, usernames: usernames, amounts: amounts }
end

def substitute_identity(text, source_tokens, customer_name_tokens, test_username, agent_name_tokens = [])
  out = text.dup
  subs = 0
  # the customer sometimes greets the OLD agent by name ("hi Shirley") — swap
  # any historical agent name (this chat's agent senders + known aliases) to the
  # current persona ("hi Bella").
  (Array(agent_name_tokens) + PERSONA_ALIASES).uniq.each do |tok|
    next if tok.to_s.length < 3 || tok.casecmp(PERSONA_NAME).zero?
    re = /(?<![a-z0-9])#{Regexp.escape(tok)}(?![a-z0-9])/i
    if out.match?(re)
      subs += 1
      out = out.gsub(re, PERSONA_NAME)
    end
  end
  (customer_name_tokens + source_tokens[:usernames].to_a).uniq.each do |tok|
    next if tok.to_s.length < 3
    re = /(?<![a-z0-9])#{Regexp.escape(tok)}(?![a-z0-9])/i
    if out.match?(re)
      subs += 1
      out = out.gsub(re, tok.match?(/\d/) ? test_username : 'Tester')
    end
  end
  if (m = out.match(/\b(?:username|user\s*name)\s*(?:is|:)?\s*([A-Za-z][A-Za-z0-9._-]{2,})/i))
    unless m[1].casecmp(test_username).zero?
      out = out.sub(m[1], test_username)
      subs += 1
    end
  end
  if out.strip.match?(/\A[A-Za-z][A-Za-z._-]*\d[A-Za-z0-9._-]*\z/) && !out.strip.casecmp(test_username).zero?
    out = test_username
    subs += 1
  end
  [out, subs]
end

# ── load + classify the corpus ───────────────────────────────────────────────
puts "\n#{'=' * 72}\nPATRA CONVO REPLAY — MODE=#{MODE}#{PARSE_ONLY ? ' (PARSE_ONLY)' : ''} dir=#{DIR}\n#{'=' * 72}"
files = Dir.glob(File.join(DIR, '**', '*.json')).sort
abort "[harness] no .json files under #{DIR}" if files.empty?
puts "[parse] #{files.size} json files"

parsed = {}
unparseable = []
sender_freq = Hash.new(0)
files.each do |f|
  r = parse_file(f)
  if r[:error]
    unparseable << [f, r[:error]]
  else
    parsed[f] = r
    r[:senders].each { |s| sender_freq[s.downcase] += 1 }
  end
end
frequent_agents = sender_freq.select { |_n, c| c > parsed.size * 0.2 }.keys.to_set
puts "[parse] parsed=#{parsed.size} unparseable=#{unparseable.size} frequent-agent-names=#{frequent_agents.to_a.inspect}"

convos = []       # [{path:, customer_turns: [...], agent_hints: [...], source_tokens:, customer_name_tokens:, filtered:, truncated:}]
side_unresolved = []
parsed.each do |path, r|
  sides = {}
  unknown = []
  r[:turns].each do |t|
    s = agent_side?(t[:who], frequent_agents)
    sides[t[:who]] = s
    unknown << t[:who] if s.nil?
  end
  if unknown.uniq.size > 1
    # more than one unresolved sender — can't split sides safely
    side_unresolved << [path, r[:senders].first(4)]
    next
  end
  # a single unresolved sender in a chat where at least one agent side exists = the customer
  customer_turns = r[:turns].select { |t| sides[t[:who]] == false || sides[t[:who]].nil? }
  agent_turns = r[:turns].select { |t| sides[t[:who]] == true }
  if customer_turns.empty? || agent_turns.empty?
    side_unresolved << [path, r[:senders].first(4)]
    next
  end
  truncated = [customer_turns.size - MAX_TURNS, 0].max
  customer_names = customer_turns.map { |t| t[:who] }.uniq
  name_tokens = customer_names.flat_map { |n| n.split(/\s+/) }.map(&:downcase)
                              .select { |tok| tok.length >= 3 && !STOPWORDS.include?(tok) }.uniq
  agent_name_tokens = agent_turns.map { |t| t[:who] }.uniq
                                 .flat_map { |n| n.split(/\s+/) }.map(&:downcase)
                                 .select { |tok| tok.length >= 3 }.uniq
  convos << {
    path: path,
    customer_turns: customer_turns.first(MAX_TURNS).map { |t| t[:text] },
    agent_hints: agent_turns.first(MAX_TURNS).map { |t| t[:text] },
    source_tokens: mine_source_tokens(r[:turns].map { |t| t[:text] }.join(' '), r[:senders]),
    customer_name_tokens: name_tokens,
    agent_name_tokens: agent_name_tokens,
    filtered: r[:filtered],
    truncated: truncated
  }
end
puts "[parse] replayable=#{convos.size} side-unresolved=#{side_unresolved.size}"

# route classification (cheap, no writes) — also feeds full-mode stratification
def classify_flows(customer_turns)
  intents = customer_turns.filter_map do |t|
    r = Games::IntentDetector.detect(t) rescue nil
    r.is_a?(Hash) ? r[:intent] : nil
  end
  classes = Set.new
  classes << :load if intents.any? { |i| %i[load load_bonus payment_sent_confirmation].include?(i) }
  classes << :bonus if intents.include?(:load_bonus)
  classes << :freeplay if intents.include?(:load_freeplay)
  classes << :cashout if intents.any? { |i| %i[cashout redeem_partial_replay].include?(i) }
  classes << :transfer if intents.include?(:transfer_between_games)
  classes << :creation if intents.any? { |i| CREATION_INTENTS.include?(i) }
  classes << :other if classes.empty?
  [intents, classes]
end

# ── PARSE_ONLY / route report helpers ────────────────────────────────────────
def write_report(sections)
  report = +"# PATRA CONVO REPLAY REPORT\n\n"
  report << "Generated: #{Time.current.iso8601} · account=#{ACCOUNT_ID} · mode=#{MODE}#{PARSE_ONLY ? ' (parse only)' : ''}\n\n"
  sections.each { |s| report << s << "\n" }
  File.write(REPORT_PATH, report)
  puts "\nREPORT -> #{REPORT_PATH}"
end

def parse_section(files, convos, unparseable, side_unresolved, frequent_agents)
  filtered_totals = Hash.new(0)
  convos.each { |c| c[:filtered].each { |k, v| filtered_totals[k] += v } }
  truncated_files = convos.count { |c| c[:truncated].positive? }
  s = +"## PARSE\n\n"
  s << "- files: #{files.size} · replayable: #{convos.size} · unparseable: #{unparseable.size} · side-unresolved: #{side_unresolved.size}\n"
  s << "- detected agent-side names (in >20% of files): #{frequent_agents.to_a.join(', ')}\n"
  s << "- customer turns: total #{convos.sum { |c| c[:customer_turns].size }}, avg #{convos.any? ? (convos.sum { |c| c[:customer_turns].size }.to_f / convos.size).round(1) : 0}/chat\n"
  s << "- noise filtered (NOT fed): #{filtered_totals.sort_by { |_k, v| -v }.map { |k, v| "#{k}=#{v}" }.join(' · ')}\n"
  s << "- chats truncated at MAX_TURNS=#{MAX_TURNS}: #{truncated_files} (overflow turns skipped, counted here — never silent)\n" if truncated_files.positive?
  if unparseable.any?
    s << "\n### Unparseable files (fix or accept)\n"
    unparseable.first(50).each { |(f, e)| s << "- #{File.basename(f)}: #{e}\n" }
    s << "- ...and #{unparseable.size - 50} more\n" if unparseable.size > 50
  end
  if side_unresolved.any?
    s << "\n### Side-unresolved files (set AGENT_NAMES=name1,name2 and re-run)\n"
    side_unresolved.first(30).each { |(f, senders)| s << "- #{File.basename(f)}: senders=#{senders.inspect}\n" }
    s << "- ...and #{side_unresolved.size - 30} more\n" if side_unresolved.size > 30
  end
  s
end

if PARSE_ONLY
  write_report([parse_section(files, convos, unparseable, side_unresolved, frequent_agents)])
  exit 0
end

# ── MODE=export — clean, paste-ready browser scripts for hand-testing ─────────
# Reads every chat, strips noise, swaps the historical username to TEST_USERNAME,
# keeps the ORIGINAL message order (the real flow), and marks each payment /
# cashout point. Safe to run locally OR on Render — it never touches the panel,
# agent_games credentials, Telegram, or the database beyond the pure-regex
# IntentDetector. Nothing is sent; nothing is charged.
if MODE == 'export'
  out_dir = ENV.fetch('EXPORT_DIR', 'test_corpus_browser_scripts')
  Dir.mkdir(out_dir) unless Dir.exist?(out_dir)
  flow_order = %i[cashout load bonus freeplay transfer creation other]
  by_flow = Hash.new { |h, k| h[k] = [] }
  index = []
  convos.each_with_index do |c, i|
    per_turn_intent = c[:customer_turns].map do |t|
      r = Games::IntentDetector.detect(t) rescue nil
      r.is_a?(Hash) ? r[:intent] : nil
    end
    _all, classes = classify_flows(c[:customer_turns])
    primary = flow_order.find { |f| classes.include?(f) } || :other
    lines = []
    c[:customer_turns].each_with_index do |t, ti|
      fed, = substitute_identity(t, c[:source_tokens], c[:customer_name_tokens], TEST_USERNAME, c[:agent_name_tokens])
      lines << "#{ti + 1}. #{fed}"
      note =
        case per_turn_intent[ti]
        when :load, :load_bonus, :load_freeplay
          '     ⮑ when Bella gives the payment handle: SEND THE REAL PAYMENT, then press paid in Telegram, then continue'
        when :cashout, :redeem_partial_replay, :replay_from_balance
          '     ⮑ a CASHOUT request will hit your Telegram group: PAY IT for real, press paid, then continue'
        when :payment_sent_confirmation
          '     ⮑ this is where you tell her you already sent it'
        end
      lines << note if note
    end
    section = +"### Chat ##{i + 1} — #{File.basename(c[:path])}   [flows: #{classes.to_a.join(', ')}]\n\n"
    section << "Use `#{TEST_USERNAME}` wherever a username is asked.\n\n"
    section << lines.join("\n") << "\n\n---\n\n"
    by_flow[primary] << section
    index << { n: i + 1, file: File.basename(c[:path]), flows: classes.to_a.join('/'),
               turns: c[:customer_turns].size, primary: primary }
  end

  by_flow.each do |flow, sections|
    header = +"# Browser test scripts — #{flow} (#{sections.size} chats)\n\n"
    header << "HOW TO USE: open the page in your browser, message it from YOUR OWN test FB account,\n"
    header << "and type each customer line below IN ORDER. Bella replies for real and real Telegram\n"
    header << "alerts fire. Where a line is marked SEND THE PAYMENT / PAY IT, do it for real and press\n"
    header << "paid in Telegram, then keep going. If a reply is wrong, note the chat number.\n\n"
    File.write(File.join(out_dir, "#{flow}.md"), header + sections.join)
  end

  idx = +"# Browser test INDEX — #{convos.size} chats (work the money flows first)\n\n"
  idx << "| # | flow(s) | turns | source file | script file |\n|---|---|---|---|---|\n"
  index.sort_by { |r| [flow_order.index(r[:primary]) || 99, -r[:turns]] }.each do |r|
    idx << "| #{r[:n]} | #{r[:flows]} | #{r[:turns]} | #{r[:file]} | #{r[:primary]}.md |\n"
  end
  File.write(File.join(out_dir, '_INDEX.md'), idx)

  puts "[export] wrote #{convos.size} browser scripts to #{out_dir}/ (one .md per flow + _INDEX.md)"
  write_report([parse_section(files, convos, unparseable, side_unresolved, frequent_agents),
                "## EXPORT\n\nWrote paste-ready browser scripts for #{convos.size} chats into `#{out_dir}/`, " \
                "grouped by flow, ordered by `_INDEX.md` (money flows first). Test username: `#{TEST_USERNAME}`.\n"])
  exit 0
end

if MODE == 'route'
  puts "\n[route] classifying #{convos.size} chats (zero LLM, zero writes)"
  intent_tally = Hash.new(0)
  flow_tally = Hash.new(0)
  unmapped = Hash.new(0)
  flows_by_file = {}
  convos.each_with_index do |c, i|
    intents, classes = classify_flows(c[:customer_turns])
    intents.each do |it|
      intent_tally[it] += 1
      unmapped[it] += 1 unless HANDLER.key?(it)
    end
    intent_tally[:_fallthrough_llm] += c[:customer_turns].size - intents.size
    classes.each { |cl| flow_tally[cl] += 1 }
    flows_by_file[c[:path]] = classes.to_a.map(&:to_s)
    puts "[route] #{i + 1}/#{convos.size}" if ((i + 1) % 250).zero?
  end
  File.write(FLOWS_CACHE, JSON.generate(flows_by_file))
  s = +"## ROUTE SWEEP (deterministic, all replayable chats)\n\n"
  s << "| flow class | chats |\n|---|---|\n"
  flow_tally.sort_by { |_k, v| -v }.each { |k, v| s << "| #{k} | #{v} |\n" }
  s << "\n| detected intent | turns |\n|---|---|\n"
  intent_tally.sort_by { |_k, v| -v }.each { |k, v| s << "| #{k} | #{v} |\n" }
  if unmapped.any?
    s << "\nWARNING — intents with NO handler mapping (routing tripwire): #{unmapped.keys.join(', ')}\n"
  else
    s << "\nAll detected intents have a handler mapping (tripwire clean).\n"
  end
  s << "\nFlow classes cached to #{FLOWS_CACHE} for MODE=full stratified sampling.\n"
  write_report([parse_section(files, convos, unparseable, side_unresolved, frequent_agents), s])
  exit 0
end

# ═════════════════════════════ REPLAY (execute / full) ═══════════════════════

# ── selection ────────────────────────────────────────────────────────────────
limit = LIMIT_ENV.positive? ? LIMIT_ENV : (MODE == 'full' ? 150 : convos.size)
selected =
  if limit >= convos.size
    convos
  elsif MODE == 'full' && File.exist?(FLOWS_CACHE)
    # stratified round-robin across flow classes from the route sweep
    flows = JSON.parse(File.read(FLOWS_CACHE)) rescue {}
    buckets = Hash.new { |h, k| h[k] = [] }
    convos.each { |c| buckets[(flows[c[:path]] || ['other']).first] << c }
    picked = []
    until picked.size >= limit || buckets.values.all?(&:empty?)
      buckets.each_value do |b|
        picked << b.shift if b.any? && picked.size < limit
      end
    end
    picked
  else
    convos.first(limit)
  end
puts "[select] replaying #{selected.size}/#{convos.size} chats (LIMIT=#{limit})"

if TELEGRAM == 'live' && selected.size > 25 && ENV['FORCE_LIVE'] != '1'
  abort "[harness] TELEGRAM=live with #{selected.size} chats would flood the group. " \
        'Use LIMIT<=25 for a live walkthrough, or FORCE_LIVE=1 to override.'
end

done = {}
if RESUME && File.exist?(CHECKPOINT)
  done = (JSON.parse(File.read(CHECKPOINT))['done'] rescue {}) || {}
  puts "[resume] #{done.size} chats already done — skipping them"
end

# ── stubs (per-thread FakeClient; recorded/limited Telegram; gated approvals) ─
$orig = {}
def stub_singleton(mod, name, &impl)
  $orig[[mod, name]] ||= (mod.respond_to?(name) ? mod.method(name) : nil)
  mod.define_singleton_method(name, &impl)
end

class FakeClient
  attr_accessor :calls
  def initialize; @calls = []; end
  def reset!; @calls = []; self; end
  def get_user_id(account_name:)
    @calls << [:get_user_id, account_name]
    { 'data' => { 'user_id' => 12_345 } }
  end
  def recharge(user_id:, amount:, order_id:)
    @calls << [:recharge, amount]
    { 'code' => 0, 'msg' => 'ok', 'data' => { 'agent_balance' => 100_000 } }
  end
  def withdraw(user_id:, amount:, order_id:)
    @calls << [:withdraw, amount]
    { 'code' => 0, 'msg' => 'ok' }
  end
  def add_user(account:, password:)
    @calls << [:add_user, account]
    { 'code' => 0, 'msg' => 'ok' }
  end
  def user_balance(user_id:)
    @calls << [:user_balance]
    { 'data' => { 'user_balance' => 50.0 } }
  end
  def agent_balance; @calls << [:agent_balance]; { 'data' => { 'agent_balance' => 100_000 } }; end
  def reset_player_password(user_id:, login_pwd:); @calls << [:reset_player_password]; { 'code' => 0 }; end
  def force_player_offline(*); { 'code' => 0 }; end
  def test_connection; { ok: true }; end
end

stub_singleton(Games::ClientRegistry, :client_for) { |_ag| Thread.current[:fake_client] ||= FakeClient.new }
raise '[harness] panel stub failed to install' unless Games::ClientRegistry.client_for(nil).is_a?(FakeClient)

TG_METHODS = %i[human_escalation load_failed load_alert cashout_alert cashout_failed api_error
                low_balance_alert payment_pending_alert secret_phrase_triggered send_raw
                send_to_cashout_group winback_manual_alert].freeze
$TG_MUTEX = Mutex.new
$TG_LIVE_SENT = 0
$TG_LIVE_TIMES = []
$TG_DEGRADED = false
TG_METHODS.each do |m|
  stub_singleton(Games::TelegramNotifier, m) do |*a, **k|
    (Thread.current[:tg_log] ||= []) << [m, k.keys]
    if TELEGRAM == 'live'
      send_it = false
      $TG_MUTEX.synchronize do
        now = Time.now.to_f
        $TG_LIVE_TIMES.reject! { |t| now - t > 60 }
        if $TG_LIVE_SENT >= TG_MAX
          $TG_DEGRADED = true
        elsif $TG_LIVE_TIMES.size < TG_RATE
          $TG_LIVE_TIMES << now
          $TG_LIVE_SENT += 1
          send_it = true
        end
      end
      if send_it && $orig[[Games::TelegramNotifier, m]]
        begin
          $orig[[Games::TelegramNotifier, m]].call(*a, **k)
        rescue StandardError => e
          puts "[tg-live] #{m} failed: #{e.class}: #{e.message[0, 80]}"
        end
      end
    end
    { ok: true }
  end
end

$LIVE_APPROVAL_IDS = []
$AP_MUTEX = Mutex.new
stub_singleton(Approvals::CashoutApprovalGate, :create_request!) do |**k|
  (Thread.current[:approval_log] ||= []) << { amount: k[:amount], keys: k.keys }
  if GATE == 'live' && $orig[[Approvals::CashoutApprovalGate, :create_request!]]
    rec = $orig[[Approvals::CashoutApprovalGate, :create_request!]].call(**k)
    $AP_MUTEX.synchronize { $LIVE_APPROVAL_IDS << rec.id if rec.respond_to?(:id) }
    rec
  else
    OpenStruct.new(id: "HARNESS_APPROVAL_#{Thread.current.object_id}")
  end
end

stub_singleton(Ai::DeepseekClient, :complete) { |**_k| nil } if MODE == 'execute'
stub_singleton(Contacts::BlacklistChecker, :blacklisted?) { |_c| false } if defined?(Contacts::BlacklistChecker)
if defined?(Payments::EmailConfirmationService)
  Payments::EmailConfirmationService.class_eval do
    unless method_defined?(:orig_check_all_convo_harness)
      alias_method :orig_check_all_convo_harness, :check_all
      def check_all
        { checked: 0, confirmed: 0 }
      end
    end
  end
end

account = Account.find(ACCOUNT_ID)
actives = account.agent_games.active.joins(:game).to_a
abort '[harness] no active agent_games on account 2' if actives.empty?
default_slug = actives.first.game.slug
active_slugs = actives.map { |a| a.game.slug }

# referral pin happens INSIDE the begin/ensure below so a crash can never
# leave referral_enabled=false behind permanently.
pref_row = ReplyPreference.for_account(ACCOUNT_ID)
saved_referral = nil
referral_pinned = false

# text Bella is allowed to echo regardless of the source chat (account config)
account_allowed = +''
begin
  account.payment_handles.to_a.each { |h| account_allowed << " #{h.try(:display_name)} #{h.try(:display_handle)}" }
rescue StandardError
  nil
end
active_slugs.each { |s| account_allowed << " #{s}" }
account_allowed = account_allowed.downcase

puts "\n[stubs] panel=FAKE (always) · telegram=#{TELEGRAM}#{TELEGRAM == 'live' ? " (rate #{TG_RATE}/min, cap #{TG_MAX})" : ''} · approvals=#{GATE} · deepseek=#{MODE == 'full' ? 'REAL' : 'stubbed'} · autoconfirm=#{AUTOCONFIRM} · preamble=#{NO_PREAMBLE ? 'off (grade the ask)' : 'on'}"

# ── replay machinery ─────────────────────────────────────────────────────────
def harness_inbox(account)
  $HARNESS_INBOX ||= account.inboxes.detect { |i| i.channel_type == 'Channel::Api' } ||
                     account.inboxes.order(:id).first
end

def new_harness_conversation(account, contact)
  inbox = harness_inbox(account)
  raise '[harness] account has no inbox' unless inbox
  ci = ContactInbox.find_by(contact_id: contact.id, inbox_id: inbox.id) ||
       ContactInbox.create!(contact: contact, inbox: inbox, source_id: SecureRandom.uuid)
  Conversation.create!(account: account, inbox: inbox, contact: contact, contact_inbox: ci)
end

# it6 A5 pattern: retry transient DeepSeek network errors with backoff.
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

def guard_parity(svc, msgs, incoming_text, reply)
  svc.instance_variable_set(:@routing_last_incoming_raw_content, incoming_text)
  svc.instance_variable_set(:@conversation_history_for_llm, msgs.map { |m| { 'role' => m[:role], 'content' => m[:content] } })
  svc.instance_variable_set(:@rag_example_leak_candidates, nil)
  svc.instance_variable_set(:@rag_leak_allowed_text, nil)
  guarded = svc.send(:guard_against_false_load_claim, reply)
  guarded.to_s.strip.empty? ? reply : guarded
rescue StandardError
  reply
end

def deepseek_turn(svc, msgs, incoming_text)
  framed = msgs.map { |m| { 'role' => m[:role], 'content' => m[:content] } }
  svc.instance_variable_set(:@conversation_history_for_llm, framed)
  svc.instance_variable_set(:@routing_last_incoming_raw_content, incoming_text)
  svc.instance_variable_set(:@rag_examples, (svc.send(:fetch_rag_examples, incoming_text, ACCOUNT_ID) rescue []))
  svc.instance_variable_set(:@reply_pref, (ReplyPreference.for_account(ACCOUNT_ID) rescue nil))
  sys = svc.send(:build_system_prompt,
                 (svc.send(:fetch_payment_info) rescue ''), (svc.send(:fetch_ai_training) rescue ''),
                 (svc.send(:fetch_ai_persona) rescue ''), (svc.send(:fetch_player_profile) rescue ''),
                 (svc.send(:fetch_all_canned_responses) rescue ''),
                 (svc.send(:needs_payment_link?, framed) rescue false), rag_examples_block: '')
  invoke_with_retry(svc, framed, sys)
end

# style graders (copied from script/patra_corpus_replay.rb Tier 2)
def style_violations(reply)
  v = []
  lines = reply.split(/\r?\n/).reject { |l| l.strip.empty? }
  v << 'over-2-lines' if lines.size > 2
  v << 'bullets-or-markdown' if lines.any? { |l| l.match?(/^\s*([-*•]|\d+[.)])\s/) } || reply.match?(/\*\*|```/)
  v << 'banned-phrase' if reply.match?(/certainly!?|great question/i)
  v << 'ai-admission' if reply.downcase.match?(/as an ai|language model|i am an ai|i'm an ai|\bai (assistant|model|bot)\b|i am a bot|i'm a bot/)
  cot = Ai::ReplyService::COT_MARKERS.select { |re| reply.match?(re) }
  v << "cot-marker(#{cot.size})" if cot.any?
  v
end

# HIGH grader: reply echoes a source-chat identity/amount that was never fed
def source_leak_hits(reply, source_tokens, fed_blob, account_allowed, test_username)
  scan = reply.to_s.downcase
  hits = []
  (source_tokens[:names] | source_tokens[:usernames]).each do |tok|
    next if tok.length < 4 || tok == test_username
    next if fed_blob.include?(tok) || account_allowed.include?(tok)
    hits << tok if scan.match?(/(?<![a-z0-9$@_.-])#{Regexp.escape(tok)}(?![a-z0-9_.-])/)
  end
  reply_amounts = scan.scan(DOLLAR_SHAPE).flatten.map { |a| a.delete(',').to_f }
  reply_amounts.concat(scan.scan(/\b(\d[\d,]{0,8}(?:\.\d{1,2})?)\s*(?:dollars?|bucks)\b/).flatten.map { |a| a.delete(',').to_f })
  fed_amounts = fed_blob.scan(/\d[\d,]{0,8}(?:\.\d{1,2})?/).map { |a| a.delete(',').to_f }
  reply_amounts.each do |amt|
    next unless source_tokens[:amounts].any? { |sa| (sa - amt).abs < 0.01 }
    next if fed_amounts.any? { |fa| (fa - amt).abs < 0.01 }
    hits << format('$%g', amt)
  end
  hits.uniq
end

$RESULTS_MUTEX = Mutex.new
$CHECKPOINT_MUTEX = Mutex.new
$done_map = done.dup
$created_contact_ids = []
$created_conversation_ids = []
$TRACK_MUTEX = Mutex.new

def checkpoint!(path, verdict)
  $CHECKPOINT_MUTEX.synchronize do
    $done_map[path] = verdict
    File.write("#{CHECKPOINT}.tmp", JSON.generate({ 'done' => $done_map }))
    File.rename("#{CHECKPOINT}.tmp", CHECKPOINT)
  end
end

def append_result!(row)
  $RESULTS_MUTEX.synchronize { File.open(RESULTS_PATH, 'a') { |f| f.puts(JSON.generate(row)) } }
end

def process_chat(c, idx, _shared_account, default_slug)
  # fresh per-thread Account instance — association caches on a shared AR
  # object are not thread-safe.
  account = Account.find(ACCOUNT_ID)
  fake = (Thread.current[:fake_client] ||= FakeClient.new).reset!
  Thread.current[:tg_log] = []
  Thread.current[:approval_log] = []
  test_username = "tester#{idx}"

  contact = Contact.create!(account: account, name: "TESTER_#{idx}")
  convo = new_harness_conversation(account, contact)
  $TRACK_MUTEX.synchronize do
    $created_contact_ids << contact.id
    $created_conversation_ids << convo.id
  end
  begin
    convo.update_labels(%w[harness-test])
  rescue StandardError
    nil
  end

  svc = Ai::ReplyService.new(convo.display_id, account_id: ACCOUNT_ID)
  cidv = contact.id
  svc.define_singleton_method(:fetch_sender_contact_id) { cidv }
  svc.define_singleton_method(:store_player_username) { |_cid| nil }
  svc.define_singleton_method(:clear_game_username) { |_cid| nil }

  msgs = []
  turn_rows = []
  violations = []
  fed_blob = +"#{test_username} tester"
  substitutions = 0

  feed = lambda do |text, synthetic: false|
    fed_blob << ' ' << text.downcase
    msgs << { role: 'user', content: text }
    detected = begin
      r = Games::IntentDetector.detect(text)
      r.is_a?(Hash) ? r[:intent] : nil
    rescue StandardError
      nil
    end
    res = begin
      Games::ConversationOrchestrator.new(
        account: account, contact: contact, conversation: convo,
        messages: msgs.map { |m| { role: m[:role], content: m[:content] } }
      ).handle
    rescue StandardError => e
      violations << "orchestrator-exception: #{e.class}: #{e.message[0, 120]}"
      nil
    end
    reply = nil
    route = 'llm(skipped)'
    if res.is_a?(Hash) && res[:reply].to_s.strip.present?
      route = 'orchestrator'
      svc.instance_variable_set(:@rag_examples, nil)
      reply = guard_parity(svc, msgs, text, res[:reply].to_s)
    elsif MODE == 'full'
      route = 'llm'
      begin
        raw = deepseek_turn(svc, msgs, text)
        reply = raw.present? ? guard_parity(svc, msgs, text, raw) : nil
      rescue StandardError => e
        violations << "deepseek-exception: #{e.class}: #{e.message[0, 120]}"
      end
    end
    msgs << { role: 'assistant', content: reply } if reply.present?
    turn_rows << { synthetic: synthetic, text: text[0, 160], intent: detected, route: route,
                   reply: reply&.slice(0, 200), reply_full: reply }
    reply
  end

  intents, classes = classify_flows(c[:customer_turns])
  wants_money = intents.any? { |i| MONEY_INTENTS.include?(i) }
  has_creation = intents.any? { |i| CREATION_INTENTS.include?(i) }

  # account-creation preamble through the REAL pipeline
  if !NO_PREAMBLE && wants_money && !has_creation
    game = c[:customer_turns].filter_map { |t| Games::IntentDetector.detect_game(t) rescue nil }.first || default_slug
    feed.call("can you make me an account on #{game}", synthetic: true)
    feed.call(test_username, synthetic: true)
    unless fake.calls.any? { |call| call[0] == :add_user }
      contact.reload
      contact.update!(custom_attributes: (contact.custom_attributes || {}).merge("game_username_#{game}" => test_username))
      violations << 'preamble-failed-primed-directly'
    end
  end

  c[:customer_turns].each do |raw_text|
    fed, subs = substitute_identity(raw_text, c[:source_tokens], c[:customer_name_tokens], test_username, c[:agent_name_tokens])
    substitutions += subs
    reply = feed.call(fed)
    next unless AUTOCONFIRM && reply.to_s.match?(/\(yes\s*\/\s*no\)/i)

    feed.call('yes', synthetic: true)
  end

  # ── grade the conversation ──
  high = []
  style = Hash.new(0)
  turn_rows.each do |t|
    full = t.delete(:reply_full).to_s # grade the FULL reply; JSONL keeps the 200-char cut
    next if full.empty?
    style_violations(full).each { |v| style[v] += 1 }
    leaks = source_leak_hits(full, c[:source_tokens], fed_blob, Thread.current[:account_allowed_blob], test_username)
    high << "source-chat-leak(#{leaks.join(',')}): #{full[0, 120]}" if leaks.any?
  end
  fake.calls.select { |call| %i[get_user_id add_user].include?(call[0]) }.each do |(_op, uname)|
    u = uname.to_s.downcase
    next if u.start_with?('tester')
    if c[:source_tokens][:usernames].include?(u)
      high << "historical-username-to-panel(#{u})"
    else
      violations << "unexpected-panel-username(#{u})"
    end
  end
  ops = fake.calls.map(&:first).tally
  tg_log = Thread.current[:tg_log] || []
  ap_log = Thread.current[:approval_log] || []
  if wants_money && ops.empty? && ap_log.empty? && tg_log.empty? &&
     turn_rows.none? { |t| t[:route] == 'orchestrator' }
    violations << 'money-intent-no-action-anywhere'
  end
  if NO_PREAMBLE && wants_money && !has_creation
    asked = turn_rows.any? { |t| t[:reply].to_s.match?(/username|account|which game|create/i) }
    violations << 'no-username-ask-before-money' unless asked
  end

  verdict = high.empty? ? 'PASS' : 'FAIL'
  row = {
    file: File.basename(c[:path]), idx: idx, verdict: verdict, flows: classes.to_a,
    turns: turn_rows.size, substitutions: substitutions, panel_ops: ops,
    telegram: tg_log.size, approvals: ap_log.size,
    high: high, violations: violations, style: style, turn_rows: turn_rows
  }
  append_result!(row)
  checkpoint!(c[:path], verdict)
  row
rescue StandardError => e
  row = { file: File.basename(c[:path]), idx: idx, verdict: 'ERROR', high: [], violations: ["chat-exception: #{e.class}: #{e.message[0, 160]}"], style: {}, flows: [], panel_ops: {}, telegram: 0, approvals: 0, turns: 0, substitutions: 0 }
  append_result!(row)
  checkpoint!(c[:path], 'ERROR')
  row
end

# ── run ──────────────────────────────────────────────────────────────────────
work = selected.each_with_index.reject { |(c, _i)| done.key?(c[:path]) }
puts "[run] #{work.size} chats to replay (#{selected.size - work.size} resumed as done)"

threads = [[ENV.fetch('THREADS', '1').to_i, 1].max, ActiveRecord::Base.connection_pool.size - 1].min
threads = 1 if threads < 1
queue = Queue.new
work.each { |item| queue << item }
results = []
$RESULTS_COLLECT_MUTEX = Mutex.new
t0 = Time.now
run_started_at = Time.current

begin
  if pref_row.respond_to?(:referral_enabled)
    saved_referral = pref_row.referral_enabled
    pref_row.update!(referral_enabled: false)
    referral_pinned = true
  end

  workers = threads.times.map do
    Thread.new do
      Thread.current[:account_allowed_blob] = account_allowed
      loop do
        item = begin
          queue.pop(true)
        rescue ThreadError
          break
        end
        c, i = item
        row = ActiveRecord::Base.connection_pool.with_connection { process_chat(c, i, account, default_slug) }
        $RESULTS_COLLECT_MUTEX.synchronize do
          results << row
          n = results.size
          puts "[run] #{n}/#{work.size} #{row[:verdict]} #{row[:file]} (#{(n / (Time.now - t0)).round(2)}/s)" if (n % 10).zero? || row[:verdict] != 'PASS'
        end
      end
    end
  end
  workers.each(&:join)

  # ── report ──
  pass = results.count { |r| r[:verdict] == 'PASS' }
  fail_n = results.count { |r| r[:verdict] == 'FAIL' }
  err_n = results.count { |r| r[:verdict] == 'ERROR' }
  style_totals = Hash.new(0)
  results.each { |r| (r[:style] || {}).each { |k, v| style_totals[k] += v } }
  flow_verdicts = Hash.new { |h, k| h[k] = { 'PASS' => 0, 'FAIL' => 0, 'ERROR' => 0 } }
  results.each { |r| (r[:flows] || [:other]).each { |f| flow_verdicts[f][r[:verdict]] += 1 } }
  ops_totals = Hash.new(0)
  results.each { |r| (r[:panel_ops] || {}).each { |k, v| ops_totals[k] += v } }

  s = +"## REPLAY (#{MODE})\n\n"
  s << "HEADLINE: #{pass} PASS / #{fail_n} FAIL / #{err_n} ERROR of #{results.size} chats replayed " \
       "(#{selected.size - work.size} previously done) · wall #{(Time.now - t0).round}s · threads #{threads}\n\n"
  s << "| flow | pass | fail | error |\n|---|---|---|---|\n"
  flow_verdicts.each { |f, v| s << "| #{f} | #{v['PASS']} | #{v['FAIL']} | #{v['ERROR']} |\n" }
  s << "\nPanel ops recorded (ALL FAKE, $0): #{ops_totals.sort_by { |_k, v| -v }.map { |k, v| "#{k}=#{v}" }.join(' · ')}\n"
  s << "Telegram: mode=#{TELEGRAM}, alerts recorded=#{results.sum { |r| r[:telegram].to_i }}" \
       "#{TELEGRAM == 'live' ? ", REALLY sent=#{$TG_LIVE_SENT}#{$TG_DEGRADED ? " (cap #{TG_MAX} hit — rest recorded only)" : ''}" : ' (nothing sent)'}\n"
  s << "Approvals: mode=#{GATE}, recorded=#{results.sum { |r| r[:approvals].to_i }}#{GATE == 'live' ? ", real rows created=#{$LIVE_APPROVAL_IDS.size} (deleted in cleanup)" : ''}\n"
  s << "Identity substitutions applied to fed texts: #{results.sum { |r| r[:substitutions].to_i }}\n"
  s << "\nStyle violations (informational): #{style_totals.sort_by { |_k, v| -v }.map { |k, v| "#{k}=#{v}" }.join(' · ')}\n" if style_totals.any?

  highs = results.flat_map { |r| (r[:high] || []).map { |h| [r[:file], h] } }
  if highs.any?
    s << "\n### HIGH violations (first 100, verbatim)\n"
    highs.first(100).each { |(f, h)| s << "- #{f}: #{h}\n" }
    s << "- ...and #{highs.size - 100} more\n" if highs.size > 100
  else
    s << "\nNo HIGH violations — no source-chat identity/amount leaked, no historical username reached the panel.\n"
  end
  meds = results.flat_map { |r| (r[:violations] || []).map { |v| [r[:file], v] } }
  if meds.any?
    s << "\n### Other findings (first 100)\n"
    meds.first(100).each { |(f, v)| s << "- #{f}: #{v}\n" }
    s << "- ...and #{meds.size - 100} more\n" if meds.size > 100
  end
  s << "\nPer-chat detail: #{RESULTS_PATH} (one JSON line per chat, includes every turn + reply)\n"
  write_report([parse_section(files, convos, unparseable, side_unresolved, frequent_agents), s])
ensure
  puts "\n[cleanup] destroying harness records…"
  begin
    ids = $created_conversation_ids.uniq
    Conversation.where(id: ids).destroy_all if ids.any?
    cids = $created_contact_ids.uniq
    GameAction.where(contact_id: cids).delete_all if cids.any?
    Contact.where(id: cids).destroy_all if cids.any?
    # defensive sweep: stray TESTER_ contacts from a crashed prior run
    stray = Contact.where(account_id: ACCOUNT_ID).where("name LIKE 'TESTER\\_%'").where.not(id: cids)
    stray_count = stray.count
    if stray_count.positive?
      stray_ids = stray.pluck(:id)
      Conversation.where(contact_id: stray_ids).destroy_all
      GameAction.where(contact_id: stray_ids).delete_all
      stray.destroy_all
      puts "[cleanup] swept #{stray_count} stray TESTER_ contacts from earlier runs"
    end
    if $LIVE_APPROVAL_IDS.any? && defined?(ApprovalRequest)
      ApprovalRequest.where(id: $LIVE_APPROVAL_IDS).delete_all
      puts "[cleanup] deleted #{$LIVE_APPROVAL_IDS.size} live approval rows"
    end
    # the orchestrator also creates ApprovalRequest rows DIRECTLY (generosity
    # payouts + over-threshold load holds), bypassing the stubbed gate — sweep
    # any that point at contacts this run created.
    all_ids = (cids + (defined?(stray_ids) && stray_ids ? stray_ids : [])).uniq
    if defined?(ApprovalRequest) && all_ids.any?
      swept = ApprovalRequest.where(account_id: ACCOUNT_ID)
                             .where('created_at >= ?', run_started_at)
                             .where("(metadata->>'contact_id' IN (?)) OR (target_type = 'Contact' AND target_id IN (?))",
                                    all_ids.map(&:to_s), all_ids)
                             .delete_all
      puts "[cleanup] swept #{swept} orchestrator-created approval rows" if swept.positive?
    end
    puts "[cleanup] removed #{ids.size} conversations, #{cids.size} contacts"
  rescue StandardError => e
    puts "[cleanup] FAILED (#{e.class}: #{e.message}) — harness records are labeled harness-test / named TESTER_*"
  end
  begin
    pref_row.update!(referral_enabled: saved_referral) if referral_pinned
  rescue StandardError => e
    puts "[cleanup] referral_enabled restore failed: #{e.message}"
  end
  $orig.each { |(mod, name), orig| mod.define_singleton_method(name, orig) if orig }
  if defined?(Payments::EmailConfirmationService) &&
     Payments::EmailConfirmationService.method_defined?(:orig_check_all_convo_harness)
    Payments::EmailConfirmationService.class_eval do
      alias_method :check_all, :orig_check_all_convo_harness
      remove_method :orig_check_all_convo_harness
    end
  end
  puts '[cleanup] stubs restored'
end
