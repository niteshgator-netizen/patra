# frozen_string_literal: true

# ─────────────────────────────────────────────────────────────────────────────
# PATRA MONEY-HANDLER HARNESS (Option A — stubbed panel client, $0 real money).
# Runs all 5 money flows through the REAL ActionExecutor + REAL orchestrator
# handlers with the panel call, Telegram, approval-record, and DeepSeek STUBBED.
# Asserts money-safety per scenario; prints PASS/FAIL.
#
#   RUN (Render Shell):  bundle exec rails runner script/patra_money_harness.rb
#
# SAFETY: NO real panel HTTP (Games::ClientRegistry.client_for stubbed to a fake),
# NO real Telegram (recorded), NO real ApprovalRequest (create_request! stubbed),
# NO network (Ai::DeepseekClient stubbed). Guard scenarios use UNSAVED AgentGame
# doubles (return before persistence) so they touch zero real records. Persisting
# scenarios use one real agent_game (snapshotted + restored) + a throwaway contact;
# every GameAction created is deleted at the end.
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
class FakeClient
  attr_accessor :cfg, :calls
  def initialize; @calls = []; @cfg = {}; end
  def reset!(cfg = {}); @calls = []; @cfg = cfg; self; end
  def called?(m); @calls.any? { |c| c[0] == m }; end
  def get_user_id(account_name:)
    @calls << [:get_user_id, account_name]
    @cfg[:user_missing] ? { 'data' => {} } : { 'data' => { 'user_id' => 12_345 } }
  end
  def recharge(user_id:, amount:, order_id:)
    @calls << [:recharge, amount]; boom(:recharge)
    { 'code' => 0, 'msg' => 'ok', 'data' => { 'agent_balance' => 100_000 } }
  end
  def withdraw(user_id:, amount:, order_id:)
    @calls << [:withdraw, amount]; boom(:withdraw); { 'code' => 0, 'msg' => 'ok' }
  end
  def add_user(account:, password:)
    @calls << [:add_user, account]; boom(:add_user); { 'code' => 0, 'msg' => 'ok' }
  end
  def user_balance(user_id:)
    @calls << [:user_balance]; { 'data' => { 'user_balance' => @cfg.fetch(:balance, 50.0) } }
  end
  def agent_balance; @calls << [:agent_balance]; { 'data' => { 'agent_balance' => 100_000 } }; end
  def reset_player_password(user_id:, login_pwd:)
    @calls << [:reset_player_password]; boom(:reset_player_password); { 'code' => 0 }
  end
  def force_player_offline(*); { 'code' => 0 }; end
  def test_connection; { ok: true }; end
  private
  def boom(m); raise StandardError, "FAKE PANEL FAIL (#{m})" if @cfg[:"fail_#{m}"]; end
end

$FAKE = FakeClient.new
$TG = []          # recorded Telegram calls: [method, kwargs]
$APPROVALS = []   # recorded approval requests
$DEEPSEEK = nil   # canned DeepSeek response (nil => transfer falls to regex)
$BLACKLIST = false

# ── install stubs ─────────────────────────────────────────────────────────────
stub_singleton(Games::ClientRegistry, :client_for) { |_ag| $FAKE }

%i[human_escalation load_failed load_alert cashout_alert cashout_failed api_error
   low_balance_alert payment_pending_alert secret_phrase_triggered send_raw
   send_to_cashout_group winback_manual_alert].each do |m|
  stub_singleton(Games::TelegramNotifier, m) { |*_a, **k| $TG << [m, k]; { ok: true } }
end

stub_singleton(Approvals::CashoutApprovalGate, :create_request!) do |**k|
  $APPROVALS << k
  OpenStruct.new(id: 'HARNESS_APPROVAL')
end

stub_singleton(Ai::DeepseekClient, :complete) { |**_k| $DEEPSEEK }

if defined?(Contacts::BlacklistChecker)
  stub_singleton(Contacts::BlacklistChecker, :blacklisted?) { |_c| $BLACKLIST }
end

# ── assert helper ─────────────────────────────────────────────────────────────
$pass = 0; $fail = 0; $fails = []
def ok!(label, cond)
  if cond then $pass += 1; puts "  PASS  #{label}"
  else $fail += 1; $fails << label; puts "  FAIL  #{label}"
  end
end
def reset_run(cfg = {}); $FAKE.reset!(cfg); $TG.clear; $APPROVALS.clear; $DEEPSEEK = nil; $BLACKLIST = false; end
def tg?(substr); $TG.any? { |(_m, k)| k.values.map(&:to_s).any? { |v| v.include?(substr) } }; end

# ── fixtures ──────────────────────────────────────────────────────────────────
account = Account.find(ACCOUNT_ID)
actives = account.agent_games.active.joins(:game).to_a
abort '[harness] no active agent_games on account 2 — cannot run' if actives.empty?
ag = actives.first
src_slug = ag.game.slug

# Transfer's normalizer re-resolves the canned plan's game strings via
# IntentDetector.detect_game, then pick_agent_game looks them up. Pick games whose
# slug self-resolves (detect_game(slug)==slug) AND is active, so the plan maps to
# real active slugs the handler can find. (Fix for the transfer (a) wiring bug.)
resolvable = actives.select { |a| Games::IntentDetector.detect_game(a.game.slug) == a.game.slug }
t_src = resolvable[0]&.game&.slug
t_tgt = resolvable[1]&.game&.slug

# snapshot the real agent_game's mutable fields (restored in ensure)
snap = { fc: ag.failure_count, lfa: ag.last_failure_at, lua: ag.last_used_at, status: ag.status }

contact = Contact.create!(account: account, name: 'HARNESS_TEST_CONTACT')

# Re-establish per-scenario state. MUST run before EACH handler scenario because:
#   (1) handle_new_account_reissue clears stored credentials, so later handlers would
#       otherwise bail with "no username on file";
#   (2) accumulated successful-cashout GameActions trip the transfer velocity guard.
# So this wipes the contact's GameActions (resets velocity + idempotency) and re-sets
# the stored game usernames for every slug the scenario needs.
def prime_contact!(contact, slugs)
  GameAction.where(contact_id: contact.id).delete_all
  attrs = {}
  slugs.compact.uniq.each_with_index { |s, i| attrs["game_username_#{s}"] = "harnessuser#{i + 1}" }
  contact.update!(custom_attributes: attrs)
end

def exec(ag, contact); Games::ActionExecutor.new(agent_game: ag, contact: contact, conversation: nil); end
def orch(account, contact, msgs); Games::ConversationOrchestrator.new(account: account, contact: contact, conversation: nil, messages: msgs); end
def double(account, game, creds = {}); AgentGame.new(account: account, game: game, status: 'active', credentials: creds); end

begin
  puts "\n#{'=' * 72}\nPATRA MONEY HARNESS  (account=#{ACCOUNT_ID}, src=#{src_slug}, tgt=#{t_tgt || 'n/a'})\n#{'=' * 72}"

  # ───────────────────────── DIRECT: load_player ─────────────────────────────
  puts "\n[load_player]"
  reset_run
  r = exec(ag, contact).load_player(game_username: 'harnessuser', amount: 25, order_id: 'HARNESS_load_ok')
  ok!('load SUCCESS => ok:true', r[:ok] == true)
  ok!('load SUCCESS => recharge called once', $FAKE.calls.count { |c| c[0] == :recharge } == 1)
  ok!('load SUCCESS => GameAction success', r[:action]&.status == 'success')

  reset_run(fail_recharge: true)
  r = exec(ag, contact).load_player(game_username: 'harnessuser', amount: 25, order_id: 'HARNESS_load_fail')
  ok!('load PANEL-FAIL => ok:false', r[:ok] == false)
  ok!('load PANEL-FAIL => GameAction failed', r[:action]&.status == 'failed')

  reset_run
  $BLACKLIST = true
  r = exec(double(account, ag.game), contact).load_player(game_username: 'x', amount: 25, order_id: 'HARNESS_load_bl')
  ok!('load BLACKLIST => code blacklisted', r[:code] == 'blacklisted')
  ok!('load BLACKLIST => panel NOT called', !$FAKE.called?(:recharge))
  $BLACKLIST = false

  reset_run
  r = exec(double(account, ag.game, 'max_load_amount' => 10), contact).load_player(game_username: 'x', amount: 999, order_id: 'HARNESS_load_lim')
  ok!('load OVER-LIMIT => ok:false', r[:ok] == false)
  ok!('load OVER-LIMIT => panel NOT called', !$FAKE.called?(:recharge))

  reset_run
  e = exec(ag, contact)
  e.load_player(game_username: 'harnessuser', amount: 25, order_id: 'HARNESS_dup')
  before = $FAKE.calls.count { |c| c[0] == :recharge }
  dup_raised = false
  begin
    exec(ag, contact).load_player(game_username: 'harnessuser', amount: 25, order_id: 'HARNESS_dup')
  rescue Games::ActionExecutor::IdempotencyError
    dup_raised = true
  end
  ok!('load DUPLICATE => IdempotencyError raised', dup_raised)
  ok!('load DUPLICATE => no second recharge', ($FAKE.calls.count { |c| c[0] == :recharge }) == before)

  # ───────────────────────── DIRECT: cashout_player ──────────────────────────
  puts "\n[cashout_player]"
  reset_run
  r = exec(ag, contact).cashout_player(game_username: 'harnessuser', amount: 25, order_id: 'HARNESS_co_ok')
  ok!('cashout SUCCESS => ok:true', r[:ok] == true)
  ok!('cashout SUCCESS => withdraw called', $FAKE.called?(:withdraw))

  reset_run(fail_withdraw: true)
  r = exec(ag, contact).cashout_player(game_username: 'harnessuser', amount: 25, order_id: 'HARNESS_co_fail')
  ok!('cashout PANEL-FAIL => ok:false', r[:ok] == false)

  reset_run
  r = exec(double(account, ag.game), contact).cashout_player(game_username: 'x', amount: 9999, order_id: 'HARNESS_co_appr')
  ok!('cashout APPROVAL => code approval_required', r[:code] == 'approval_required')
  ok!('cashout APPROVAL => withdraw NOT called', !$FAKE.called?(:withdraw))
  ok!('cashout APPROVAL => no GameAction persisted (returned pre-create)', r[:action].nil?)

  # ───────────────────────── DIRECT: add_player ──────────────────────────────
  puts "\n[add_player]  (note: real add_player sleeps 1s for verification)"
  reset_run
  r = exec(ag, contact).add_player(game_username: 'harnessnew1', password: 'pw12345', order_id: 'HARNESS_add_ok')
  ok!('add SUCCESS => ok:true', r[:ok] == true)
  ok!('add SUCCESS => add_user called', $FAKE.called?(:add_user))

  reset_run(fail_add_user: true)
  r = exec(ag, contact).add_player(game_username: 'harnessnew2', password: 'pw12345', order_id: 'HARNESS_add_fail')
  ok!('add PANEL-FAIL => ok:false', r[:ok] == false)

  reset_run(user_missing: true)   # add_user "ok" but verification (get_user_id) finds nothing
  r = exec(ag, contact).add_player(game_username: 'harnessnew3', password: 'pw12345', order_id: 'HARNESS_add_silent')
  ok!('add SILENT-FAIL => ok:false code silent_fail', r[:ok] == false && r[:code] == 'silent_fail')

  # ───────────────────────── ORCHESTRATOR: reissue ───────────────────────────
  puts "\n[handle_new_account_reissue]"
  reset_run; prime_contact!(contact, [src_slug])
  r = orch(account, contact, []).send(:handle_new_account_reissue, { intent: :new_account_reissue, game_slug: src_slug })
  ok!('reissue SUCCESS => add_user called + reply has username', $FAKE.called?(:add_user) && r[:reply].to_s.include?('username'))

  reset_run(fail_add_user: true); prime_contact!(contact, [src_slug])
  r = orch(account, contact, []).send(:handle_new_account_reissue, { intent: :new_account_reissue, game_slug: src_slug })
  ok!('reissue FAIL => needs-human + Telegram escalated', Array(r[:labels]).include?('needs-human') && $TG.any?)

  # ───────────────────────── ORCHESTRATOR: replay (READ-ONLY) ─────────────────
  puts "\n[handle_replay_from_balance]  (must move NO money)"
  reset_run(balance: 75.0); prime_contact!(contact, [src_slug])
  r = orch(account, contact, []).send(:handle_replay_from_balance, { intent: :replay_from_balance, game_slug: src_slug })
  ok!('replay => reply mentions balance, good to play', r[:reply].to_s.match?(/good to play|\$75/i))
  ok!('replay => NO withdraw/recharge (read-only)', !$FAKE.called?(:withdraw) && !$FAKE.called?(:recharge))

  # ───────────────────────── ORCHESTRATOR: redeem-partial ─────────────────────
  puts "\n[handle_redeem_partial_replay]"
  reset_run; prime_contact!(contact, [src_slug])
  r = orch(account, contact, [{ 'role' => 'user', 'content' => 'cash out 20 and keep the rest' }])
        .send(:handle_redeem_partial_replay, { intent: :redeem_partial_replay, game_slug: src_slug })
  ok!('redeem-partial SUCCESS => withdraw called + partial reply', $FAKE.called?(:withdraw) && r[:reply].to_s.match?(/cashed out/i))

  reset_run; prime_contact!(contact, [src_slug])
  r = orch(account, contact, [{ 'role' => 'user', 'content' => 'cash out 9999 keep rest' }])
        .send(:handle_redeem_partial_replay, { intent: :redeem_partial_replay, game_slug: src_slug })
  ok!('redeem-partial APPROVAL => withdraw NOT called + needs-human', !$FAKE.called?(:withdraw) && Array(r[:labels]).include?('needs-human'))

  # ───────────────────────── ORCHESTRATOR: transfer ──────────────────────────
  if t_src && t_tgt && t_src != t_tgt
    puts "\n[handle_transfer_between_games]  (src=#{t_src}, tgt=#{t_tgt})"
    plan = %({"source_game":"#{t_src}","cashout_amount":50,"loads":[{"game":"#{t_tgt}","amount":50}]})
    msgs = [{ 'role' => 'user', 'content' => "transfer 50 from #{t_src} to #{t_tgt}" }]

    reset_run(balance: 1000.0); prime_contact!(contact, [t_src, t_tgt]); $DEEPSEEK = plan
    r = orch(account, contact, msgs).send(:handle_transfer_between_games, { intent: :transfer_between_games })
    ok!('transfer SUCCESS => withdraw + recharge both called', $FAKE.called?(:withdraw) && $FAKE.called?(:recharge))
    ok!('transfer SUCCESS => reply says cashed out + loaded', r[:reply].to_s.match?(/cashed out.*loaded|done/i))

    reset_run(balance: 1000.0, fail_recharge: true); prime_contact!(contact, [t_src, t_tgt]); $DEEPSEEK = plan
    r = orch(account, contact, msgs).send(:handle_transfer_between_games, { intent: :transfer_between_games })
    ok!('transfer CASHOUT-OK/LOAD-FAIL => withdraw called (cashout happened)', $FAKE.called?(:withdraw))
    ok!('transfer CASHOUT-OK/LOAD-FAIL => Telegram reports REMAINING (not silently lost)',
        tg?('Remaining') || tg?('cashed out, tell player'))

    reset_run(balance: 0.0); prime_contact!(contact, [t_src, t_tgt]); $DEEPSEEK = plan
    r = orch(account, contact, msgs).send(:handle_transfer_between_games, { intent: :transfer_between_games })
    ok!('transfer EMPTY BALANCE => nothing to move, NO withdraw', !$FAKE.called?(:withdraw) && r[:reply].to_s.match?(/empty|nothing/i))

    reset_run(balance: 1000.0); prime_contact!(contact, [t_src, t_tgt])
    over = %({"source_game":"#{t_src}","cashout_amount":50,"loads":[{"game":"#{t_tgt}","amount":5000}]})
    $DEEPSEEK = over
    r = orch(account, contact, [{ 'role' => 'user', 'content' => "move 5000 from #{t_src} to #{t_tgt}" }])
          .send(:handle_transfer_between_games, { intent: :transfer_between_games })
    ok!('transfer OVER-AMOUNT (req>balance) => short guard, NO withdraw', !$FAKE.called?(:withdraw) && r[:reply].to_s.match?(/short of/i))
  else
    puts "\n[handle_transfer_between_games]  SKIPPED — need 2 self-resolving active agent_games on account 2"
  end

  # ───────────────────────── summary ─────────────────────────────────────────
  puts "\n#{'=' * 72}"
  puts "MONEY HARNESS: #{$pass} passed, #{$fail} failed"
  $fails.each { |f| puts "  ✗ #{f}" }
  puts "RESULT: #{$fail.zero? ? 'PASS' : 'FAIL'}"
  puts '=' * 72
ensure
  # ── cleanup: delete all test GameActions, restore the real agent_game, drop contact ──
  begin
    deleted = GameAction.where(contact_id: contact.id).delete_all
    puts "[cleanup] deleted #{deleted} test GameAction(s) for throwaway contact #{contact.id}"
  rescue StandardError => e
    puts "[cleanup] GameAction delete failed: #{e.class}: #{e.message}"
  end
  begin
    ag.update_columns(failure_count: snap[:fc], last_failure_at: snap[:lfa],
                      last_used_at: snap[:lua], status: snap[:status])
    puts "[cleanup] restored agent_game #{ag.id} (#{src_slug}) snapshot"
  rescue StandardError => e
    puts "[cleanup] agent_game restore failed: #{e.class}: #{e.message}"
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
