# frozen_string_literal: true

# ─────────────────────────────────────────────────────────────────────────────
# PATRA MONEY PRE-FLIGHT — FAILURE-PATH + RECONCILIATION harness ($0 real money).
#
# Sibling to script/patra_money_harness.rb (which proved 39/39 basic safety).
# This one drives the MESSY money paths a real-dollar test would expose — the
# cases the last live test failed on:
#   A. LOAD FAILS mid-flow            → no false success, GameAction='failed'
#   B. CASHOUT OK but LOAD FAILS      → real Remaining reported, NOT "done" (Finding-1)
#   C. PARTIAL multi-load (one fails) → only successes counted, real remaining
#   D. IDEMPOTENCY under retry        → same order_id twice = no double-charge
#   E. TELEGRAM-REMAINING accuracy    → $TG reflects TRUE state ($0 only if all ok)
#
#   RUN (Render Shell):  bundle exec rails runner script/patra_money_preflight.rb
#
# SAFETY — identical stub model to the base harness:
#   • Games::ClientRegistry.client_for → FakeClient (NO real panel HTTP).
#   • Games::TelegramNotifier.* recorded into $TG (NO real Telegram).
#   • Approvals::CashoutApprovalGate.create_request! stubbed (NO real approval).
#   • Ai::DeepseekClient.complete → canned plan JSON (NO network).
#   • Real agent_games snapshotted + restored in ensure; throwaway contact;
#     every GameAction created is deleted at the end. Touches no real money.
#
# This script edits NO production code. If a reconciliation GAP is found it is
# REPORTED here in the output, not fixed (fixes are a separate, careful change).
# ─────────────────────────────────────────────────────────────────────────────

require 'ostruct'

ACCOUNT_ID = 2

# ── stubs registry (save originals, restore in ensure) ────────────────────────
$orig = {}
def stub_singleton(mod, name, &impl)
  $orig[[mod, name]] ||= (mod.respond_to?(name) ? mod.method(name) : nil)
  mod.define_singleton_method(name, &impl)
end
def restore_stubs
  $orig.each do |(mod, name), orig|
    mod.define_singleton_method(name, orig) if orig
  end
end

# ── fake panel client (the chokepoint) ────────────────────────────────────────
# Same fail-on-command model as the base harness, PLUS per-call recharge failure
# (recharge_fail_nth: [2] fails ONLY the 2nd recharge) so we can drive a PARTIAL
# multi-load where one load succeeds and a later one fails.
class FakeClient
  attr_accessor :cfg, :calls
  def initialize; @calls = []; @cfg = {}; end
  def reset!(cfg = {}); @calls = []; @cfg = cfg; self; end
  def called?(m); @calls.any? { |c| c[0] == m }; end
  def count_of(m); @calls.count { |c| c[0] == m }; end
  def get_user_id(account_name:)
    @calls << [:get_user_id, account_name]
    @cfg[:user_missing] ? { 'data' => {} } : { 'data' => { 'user_id' => 12_345 } }
  end
  def recharge(user_id:, amount:, order_id:)
    @calls << [:recharge, amount]
    n = count_of(:recharge)
    if @cfg[:fail_recharge] || Array(@cfg[:recharge_fail_nth]).include?(n)
      raise StandardError, "FAKE PANEL FAIL (recharge ##{n})"
    end
    { 'code' => 0, 'msg' => 'ok', 'data' => { 'agent_balance' => 100_000 } }
  end
  def withdraw(user_id:, amount:, order_id:)
    @calls << [:withdraw, amount]
    raise StandardError, 'FAKE PANEL FAIL (withdraw)' if @cfg[:fail_withdraw]
    { 'code' => 0, 'msg' => 'ok' }
  end
  def add_user(account:, password:)
    @calls << [:add_user, account]
    raise StandardError, 'FAKE PANEL FAIL (add_user)' if @cfg[:fail_add_user]
    { 'code' => 0, 'msg' => 'ok' }
  end
  def user_balance(user_id:)
    @calls << [:user_balance]; { 'data' => { 'user_balance' => @cfg.fetch(:balance, 50.0) } }
  end
  def agent_balance; @calls << [:agent_balance]; { 'data' => { 'agent_balance' => 100_000 } }; end
  def reset_player_password(user_id:, login_pwd:); @calls << [:reset_player_password]; { 'code' => 0 }; end
  def force_player_offline(*); { 'code' => 0 }; end
  def test_connection; { ok: true }; end
end

$FAKE = FakeClient.new
$TG = []          # recorded Telegram calls: [method, kwargs]
$APPROVALS = []
$DEEPSEEK = nil

# ── install stubs ─────────────────────────────────────────────────────────────
stub_singleton(Games::ClientRegistry, :client_for) { |_ag| $FAKE }

%i[human_escalation load_failed load_alert cashout_alert cashout_failed api_error
   low_balance_alert payment_pending_alert secret_phrase_triggered send_raw
   send_to_cashout_group winback_manual_alert].each do |m|
  stub_singleton(Games::TelegramNotifier, m) { |*_a, **k| $TG << [m, k]; { ok: true } }
end

stub_singleton(Approvals::CashoutApprovalGate, :create_request!) do |**k|
  $APPROVALS << k
  OpenStruct.new(id: 'PREFLIGHT_APPROVAL')
end

stub_singleton(Ai::DeepseekClient, :complete) { |**_k| $DEEPSEEK }

# ── assert helper ─────────────────────────────────────────────────────────────
$pass = 0; $fail = 0; $fails = []
def ok!(label, cond)
  if cond then $pass += 1; puts "  PASS  #{label}"
  else $fail += 1; $fails << label; puts "  FAIL  #{label}"
  end
end
def reset_run(cfg = {}); $FAKE.reset!(cfg); $TG.clear; $APPROVALS.clear; $DEEPSEEK = nil; end
def tg_text; $TG.map { |(_m, k)| k.values.map(&:to_s).join(' ') }.join(' | '); end
def tg?(substr); tg_text.include?(substr); end

# ── fixtures (mirror the base harness) ────────────────────────────────────────
account = Account.find(ACCOUNT_ID)
actives = account.agent_games.active.joins(:game).to_a
abort '[preflight] no active agent_games on account 2 — cannot run' if actives.empty?
ag = actives.first
src_slug = ag.game.slug

# Transfer needs slugs that self-resolve (detect_game(slug)==slug) AND are active,
# so the canned plan maps to real active slugs the handler can find.
resolvable = actives.select { |a| Games::IntentDetector.detect_game(a.game.slug) == a.game.slug }
t_src = resolvable[0]&.game&.slug
t_t1  = resolvable[1]&.game&.slug
t_t2  = resolvable[2]&.game&.slug

# snapshot every real agent_game we might mutate (failure_count etc.), restore in ensure
mutated = ([ag] + resolvable[0, 3]).compact.uniq
snaps = mutated.to_h { |g| [g.id, { fc: g.failure_count, lfa: g.last_failure_at, lua: g.last_used_at, status: g.status }] }

contact = Contact.create!(account: account, name: 'PREFLIGHT_TEST_CONTACT')

# Wipe the contact's GameActions (resets cashout-dedup + velocity + idempotency)
# and re-set the stored usernames for the slugs a scenario needs. MUST run before
# every transfer scenario or a prior $50 cashout trips recent_cashout_duplicate?.
def prime_contact!(contact, slugs)
  GameAction.where(contact_id: contact.id).delete_all
  attrs = {}
  slugs.compact.uniq.each_with_index { |s, i| attrs["game_username_#{s}"] = "preflightuser#{i + 1}" }
  contact.update!(custom_attributes: attrs)
end

def exec(ag, contact); Games::ActionExecutor.new(agent_game: ag, contact: contact, conversation: nil); end
def orch(account, contact, msgs); Games::ConversationOrchestrator.new(account: account, contact: contact, conversation: nil, messages: msgs); end

begin
  puts "\n#{'=' * 72}\nPATRA MONEY PRE-FLIGHT  (account=#{ACCOUNT_ID})\n" \
       "src=#{src_slug}  transfer: src=#{t_src} t1=#{t_t1} t2=#{t_t2}\n#{'=' * 72}"
  puts "\n>>> FAILURE-PATH + RECONCILIATION PRE-FLIGHT <<<"

  # ─────────────────────── A. LOAD FAILS mid-flow ────────────────────────────
  # Executor-level proof: a failed load NEVER reports success.
  puts "\n[A] LOAD FAILS mid-flow (no false success)"
  reset_run(fail_recharge: true)
  r = exec(ag, contact).load_player(game_username: 'preflightuser', amount: 25, order_id: 'PF_A_loadfail')
  ok!('A: load FAIL => ok:false', r[:ok] == false)
  ok!('A: load FAIL => GameAction status=failed (not success)', r[:action]&.status == 'failed')
  ok!('A: load FAIL => recharge WAS attempted (reached panel)', $FAKE.called?(:recharge))
  ok!('A: load FAIL => no "success" leaked in result', r[:response].nil? && r[:ok] != true)

  # ──────────────── B. CASHOUT OK but LOAD FAILS (Finding-1) ──────────────────
  if t_src && t_t1 && t_src != t_t1
    puts "\n[B] CASHOUT OK / LOAD FAIL — real reconciliation (src=#{t_src} -> #{t_t1})"
    plan = %({"source_game":"#{t_src}","cashout_amount":50,"loads":[{"game":"#{t_t1}","amount":50}]})
    msgs = [{ 'role' => 'user', 'content' => "transfer 50 from #{t_src} to #{t_t1}" }]

    reset_run(balance: 1000.0, fail_recharge: true); prime_contact!(contact, [t_src, t_t1]); $DEEPSEEK = plan
    r = orch(account, contact, msgs).send(:handle_transfer_between_games, { intent: :transfer_between_games })
    ok!('B: withdraw happened (cashout succeeded)', $FAKE.called?(:withdraw))
    ok!('B: load WAS attempted then failed (recharge called)', $FAKE.called?(:recharge))
    ok!('B: reply does NOT claim full success ("done")', !r[:reply].to_s.match?(/\bdone\b/i))
    ok!('B: NOT labelled transfer-complete', !Array(r[:labels]).include?('transfer-complete'))
    ok!('B: escalated to a human (needs-human)', Array(r[:labels]).include?('needs-human'))
    ok!('B: Telegram reports FAILED (load failure surfaced)', tg?('FAILED'))
    ok!('B: Telegram reports REAL remaining $50 (full amount unaccounted)', tg?('Remaining: $50'))
    ok!('B: Telegram does NOT falsely say "$0 — fully loaded"', !tg?('Remaining: $0'))
  else
    puts "\n[B] SKIPPED — need 2 self-resolving active agent_games on account 2"
  end

  # ──────────────── C. PARTIAL multi-load (one of two fails) ──────────────────
  if t_src && t_t1 && t_t2 && [t_src, t_t1, t_t2].uniq.length == 3
    puts "\n[C] PARTIAL multi-load — load1 OK, load2 FAIL (#{t_src} -> #{t_t1}+#{t_t2})"
    plan = %({"source_game":"#{t_src}","cashout_amount":50,) +
           %("loads":[{"game":"#{t_t1}","amount":25},{"game":"#{t_t2}","amount":25}]})
    msgs = [{ 'role' => 'user', 'content' => "split 50 from #{t_src} onto #{t_t1} and #{t_t2}" }]

    reset_run(balance: 1000.0, recharge_fail_nth: [2]); prime_contact!(contact, [t_src, t_t1, t_t2]); $DEEPSEEK = plan
    r = orch(account, contact, msgs).send(:handle_transfer_between_games, { intent: :transfer_between_games })
    ok!('C: withdraw happened (cashout $50)', $FAKE.called?(:withdraw))
    ok!('C: BOTH loads attempted (recharge called twice)', $FAKE.count_of(:recharge) == 2)
    ok!('C: only the SUCCESS counted — Telegram shows one OK', tg?('OK'))
    ok!('C: the failure counted individually — Telegram shows FAILED', tg?('FAILED'))
    ok!('C: real remaining = the failed $25 (not $0, not $50)', tg?('Remaining: $25'))
    ok!('C: customer told about leftover (partial)', r[:reply].to_s.match?(/left over|couldn.?t get/i))
    ok!('C: labelled transfer-partial + needs-human', Array(r[:labels]).include?('needs-human') && Array(r[:labels]).include?('transfer-partial'))
    ok!('C: NOT falsely "fully loaded"', !tg?('fully loaded'))
  else
    puts "\n[C] SKIPPED — need 3 self-resolving active agent_games on account 2 (have #{resolvable.size})"
  end

  # ──────────────── D. IDEMPOTENCY under retry (no double-charge) ─────────────
  puts "\n[D] IDEMPOTENCY — same order_id twice = no double recharge"
  reset_run
  exec(ag, contact).load_player(game_username: 'preflightuser', amount: 25, order_id: 'PF_D_retry')
  first = $FAKE.count_of(:recharge)
  dup_raised = false
  begin
    exec(ag, contact).load_player(game_username: 'preflightuser', amount: 25, order_id: 'PF_D_retry')
  rescue Games::ActionExecutor::IdempotencyError
    dup_raised = true
  end
  ok!('D: 2nd call with same order_id raises IdempotencyError', dup_raised)
  ok!('D: NO second recharge (no double-charge)', $FAKE.count_of(:recharge) == first)
  ok!('D: first load actually charged once', first == 1)

  # ──────────────── E. TELEGRAM-REMAINING accuracy (true state) ───────────────
  if t_src && t_t1 && t_src != t_t1
    puts "\n[E] TELEGRAM-REMAINING accuracy — $0 only when ALL confirmed"
    plan = %({"source_game":"#{t_src}","cashout_amount":50,"loads":[{"game":"#{t_t1}","amount":50}]})
    msgs = [{ 'role' => 'user', 'content' => "transfer 50 from #{t_src} to #{t_t1}" }]

    # E1 — full success: Telegram MUST say fully loaded / $0, reply says done, NO FAILED.
    reset_run(balance: 1000.0); prime_contact!(contact, [t_src, t_t1]); $DEEPSEEK = plan
    r = orch(account, contact, msgs).send(:handle_transfer_between_games, { intent: :transfer_between_games })
    ok!('E1: full success => Telegram "Remaining: $0 — fully loaded"', tg?('Remaining: $0') && tg?('fully loaded'))
    ok!('E1: full success => Telegram has NO FAILED', !tg?('FAILED'))
    ok!('E1: full success => reply says done', r[:reply].to_s.match?(/\bdone\b/i))

    # E2 — load fails: Telegram MUST reflect the true non-zero remaining.
    reset_run(balance: 1000.0, fail_recharge: true); prime_contact!(contact, [t_src, t_t1]); $DEEPSEEK = plan
    orch(account, contact, msgs).send(:handle_transfer_between_games, { intent: :transfer_between_games })
    ok!('E2: load fail => Telegram shows true remaining $50 (not $0)', tg?('Remaining: $50') && !tg?('Remaining: $0'))
    ok!('E2: load fail => Telegram flags FAILED', tg?('FAILED'))
  else
    puts "\n[E] SKIPPED — need 2 self-resolving active agent_games on account 2"
  end

  # ─────────────────────────── summary ───────────────────────────────────────
  puts "\n#{'=' * 72}"
  puts "MONEY PRE-FLIGHT: #{$pass} passed, #{$fail} failed"
  $fails.each { |f| puts "  ✗ #{f}" }
  puts "RESULT: #{$fail.zero? ? 'PASS' : 'FAIL'}"
  puts '=' * 72
ensure
  begin
    deleted = GameAction.where(contact_id: contact.id).delete_all
    puts "[cleanup] deleted #{deleted} test GameAction(s) for throwaway contact #{contact.id}"
  rescue StandardError => e
    puts "[cleanup] GameAction delete failed: #{e.class}: #{e.message}"
  end
  snaps.each do |gid, s|
    g = mutated.find { |x| x.id == gid }
    next unless g

    begin
      g.update_columns(failure_count: s[:fc], last_failure_at: s[:lfa], last_used_at: s[:lua], status: s[:status])
      puts "[cleanup] restored agent_game #{gid} snapshot"
    rescue StandardError => e
      puts "[cleanup] agent_game #{gid} restore failed: #{e.class}: #{e.message}"
    end
  end
  begin
    contact.destroy
    puts '[cleanup] deleted throwaway contact'
  rescue StandardError => e
    puts "[cleanup] contact delete failed: #{e.class}: #{e.message}"
  end
  restore_stubs
  puts '[cleanup] restored stubs'
end
