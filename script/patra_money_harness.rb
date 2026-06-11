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

# MONEYFLOWS R1 fixture (assertions unchanged - see PATRA_MONEYFLOWS_LOG.md D6):
# scenarios pin transfer_mode per scenario; the saved value is restored in ensure.
pref_row = ReplyPreference.for_account(account.id)
r1_saved_mode = pref_row.transfer_mode

# MONEYFLOWS R7 fixture pin (assertions unchanged - see log D6): the legacy F13
# scenario loads $999 with the per-agent cap unset; pin the new dollar threshold
# high so F13 keeps testing the per-agent cap. R7 scenarios set their own values.
r7_acct_saved = (account.custom_attributes || {}).dup
account.update!(custom_attributes: r7_acct_saved.merge('auto_load_threshold' => 1_000_000))

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

  # DEDUP (Finding-2): a 2nd identical cashout within the window must be BLOCKED. Note we
  # do NOT prime_contact! between the paired calls — the 1st cashout's GameAction must persist.
  reset_run; prime_contact!(contact, [src_slug])   # clean slate, then call once (success)
  dmsg = [{ 'role' => 'user', 'content' => 'cash out 20 and keep the rest' }]
  orch(account, contact, dmsg).send(:handle_redeem_partial_replay, { intent: :redeem_partial_replay, game_slug: src_slug })
  reset_run   # clears fake call-log/cfg but KEEPS the GameAction just created
  r = orch(account, contact, dmsg).send(:handle_redeem_partial_replay, { intent: :redeem_partial_replay, game_slug: src_slug })
  ok!('redeem-partial DUPLICATE => 2nd withdraw BLOCKED', !$FAKE.called?(:withdraw))
  ok!('redeem-partial DUPLICATE => reply says already processing', r[:reply].to_s.match?(/already processing|hang tight/i))
  # CONTROL: a DIFFERENT amount must still go through (guard is not over-blocking)
  reset_run
  r = orch(account, contact, [{ 'role' => 'user', 'content' => 'cash out 35 keep rest' }])
        .send(:handle_redeem_partial_replay, { intent: :redeem_partial_replay, game_slug: src_slug })
  ok!('redeem-partial CONTROL (diff amount) => still withdraws', $FAKE.called?(:withdraw))

  # ───────────────────────── ORCHESTRATOR: transfer ──────────────────────────
  if t_src && t_tgt && t_src != t_tgt
    puts "\n[handle_transfer_between_games]  (src=#{t_src}, tgt=#{t_tgt})"
    # MONEYFLOWS R1 fixture pin (assertions unchanged): these legacy scenarios have
    # zero deposit history and were written for whole-balance transfer semantics.
    pref_row.update!(transfer_mode: 'whole')
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

    # DEDUP (Finding-2): a 2nd identical transfer within the window must skip BOTH the
    # cashout AND the load. Do NOT prime between the paired calls (the cashout must persist).
    reset_run(balance: 1000.0); prime_contact!(contact, [t_src, t_tgt]); $DEEPSEEK = plan   # clean, call once
    orch(account, contact, msgs).send(:handle_transfer_between_games, { intent: :transfer_between_games })
    reset_run(balance: 1000.0); $DEEPSEEK = plan   # keep GameActions, reset fake
    r = orch(account, contact, msgs).send(:handle_transfer_between_games, { intent: :transfer_between_games })
    ok!('transfer DUPLICATE => 2nd cashout BLOCKED (no withdraw)', !$FAKE.called?(:withdraw))
    ok!('transfer DUPLICATE => no load either (returned before STEP 1)', !$FAKE.called?(:recharge))
    ok!('transfer DUPLICATE => reply says already processing', r[:reply].to_s.match?(/already processing|hang tight/i))
  else
    puts "\n[handle_transfer_between_games]  SKIPPED — need 2 self-resolving active agent_games on account 2"
  end

  # ───────────────────────── F12: deterministic payment order_id ──────────────
  puts "\n[F12 deterministic order_id]  (same payment can never double-load)"
  reset_run; prime_contact!(contact, [src_slug])
  o12 = orch(account, contact, [])
  id_a = o12.send(:deterministic_payment_order_id, 'HARNESS_PAY_1')
  id_b = o12.send(:deterministic_payment_order_id, 'HARNESS_PAY_1')
  ok!('F12 same payment pre-insert => identical order_id (race collapses)', id_a == id_b && id_a.to_s.start_with?('pay'))
  id_other = o12.send(:deterministic_payment_order_id, 'HARNESS_PAY_2')
  ok!('F12 different payment => different order_id', id_other != id_a)

  # Simulated race: both "processes" computed the same id before either inserted.
  # The DB unique index (migration 20260513030000:29) lets exactly one execute.
  r1 = exec(ag, contact).load_player(game_username: 'harnessuser1', amount: 20, order_id: id_a)
  loser_blocked = false
  begin
    exec(ag, contact).load_player(game_username: 'harnessuser1', amount: 20, order_id: id_b)
  rescue Games::ActionExecutor::IdempotencyError, ActiveRecord::RecordNotUnique
    loser_blocked = true
  end
  ok!('F12 RACE same payment => exactly one recharge, loser blocked',
      r1[:ok] == true && loser_blocked && $FAKE.calls.count { |c| c[0] == :recharge } == 1)
  ok!('F12 rerun after success => helper returns nil (already-loaded skip)',
      o12.send(:deterministic_payment_order_id, 'HARNESS_PAY_1').nil?)
  r3 = exec(ag, contact).load_player(game_username: 'harnessuser1', amount: 20, order_id: id_other)
  ok!('F12 different payment unaffected => still loads', r3[:ok] == true)
  # Money invariants (R2): executions == success GameActions; no order_id twice
  succ = GameAction.where(contact_id: contact.id, action_type: 'load', status: 'success').count
  recharges = $FAKE.calls.count { |c| c[0] == :recharge }
  ok!('F12 INVARIANT recharge calls == success actions == 2', recharges == 2 && succ == 2)

  # ───────────────────────── F13: auto-load cap on the AUTOMATED path ─────────
  # Verified enforcement point: ActionExecutor#load_player:71-72 ->
  # amount_limit_error('max_load_amount') BEFORE any GameAction/panel call; the
  # orchestrator's automated path only loads via executor.load_player.
  puts "\n[F13 per-agent auto-load cap]  (automated orchestrator path)"
  reset_run
  prime_contact!(contact, [src_slug])
  contact.update!(custom_attributes: contact.custom_attributes.merge(
    'patra_finance_logs' => [{
      'id' => 'HARNESS_PAY_CAP', 'status' => 'confirmed', 'amount' => 999,
      'recorded_at' => Time.current.iso8601, 'platform' => 'cashapp'
    }]
  ))
  saved_creds = ag.credentials.to_h
  begin
    ag.update!(credentials: saved_creds.merge('max_load_amount' => 10))
    r = orch(account, contact, [{ 'role' => 'user', 'content' => 'load 999' }])
          .send(:handle_load_intent, { intent: :load, amount: 999, game_slug: src_slug, game_username: 'harnessuser1' })
    ok!('F13 OVER-CAP automated => NO recharge (no load executed)', !$FAKE.called?(:recharge))
    ok!('F13 OVER-CAP automated => needs-human label', Array(r && r[:labels]).include?('needs-human'))
    ok!('F13 OVER-CAP automated => Telegram escalation fired', $TG.any?)
  ensure
    ag.update!(credentials: saved_creds)
  end

  # Unset cap = unlimited (operator default, kept): same payment, no cap set
  reset_run
  prime_contact!(contact, [src_slug])
  contact.update!(custom_attributes: contact.custom_attributes.merge(
    'patra_finance_logs' => [{
      'id' => 'HARNESS_PAY_CAP2', 'status' => 'confirmed', 'amount' => 999,
      'recorded_at' => Time.current.iso8601, 'platform' => 'cashapp'
    }]
  ))
  begin
    ag.update!(credentials: saved_creds.reject { |k, _| k.to_s == 'max_load_amount' })
    r = orch(account, contact, [{ 'role' => 'user', 'content' => 'load 999' }])
          .send(:handle_load_intent, { intent: :load, amount: 999, game_slug: src_slug, game_username: 'harnessuser1' })
    ok!('F13 UNSET CAP => load executes (unlimited default kept)', $FAKE.called?(:recharge) && Array(r && r[:labels]).include?('auto-load'))
  ensure
    ag.update!(credentials: saved_creds)
  end

  # ───────────────────────── F15: approval auto-resume (shipped dark) ─────────
  puts "\n[F15 approval auto-resume]  (PATRA_APPROVAL_AUTORESUME-gated, appr_<id> idempotent)"
  f15_user = account.account_users.first&.user
  if f15_user.nil?
    puts '  SKIPPED - no user on account'
  else
    f15_approvals = []
    f15_saved_flag = ENV['PATRA_APPROVAL_AUTORESUME']
    begin
      mk_approval = lambda do |amount|
        a = ApprovalRequest.create!(
          account: account, requesting_user: f15_user, action_type: 'cashout',
          target_type: 'AgentGame', target_id: ag.id, amount: amount, status: 'pending',
          metadata: { 'game_username' => 'harnessuser1', 'game_name' => ag.game.name }
        )
        f15_approvals << a
        a
      end
      cashout_tg = -> { $TG.any? { |(m, _k)| m == :send_to_cashout_group } }

      # FLAG OFF (default): approving executes nothing — current manual behavior
      ENV['PATRA_APPROVAL_AUTORESUME'] = 'false'
      reset_run; prime_contact!(contact, [src_slug])
      a_off = mk_approval.call(600)
      a_off.update_columns(status: 'approved') # update_columns: no callback fires in-harness
      r = Approvals::AutoResume.execute!(a_off)
      ok!('F15 FLAG OFF => skipped, no withdraw', r[:skipped] == :disabled && !$FAKE.called?(:withdraw))

      # FLAG ON: approve executes exactly once, approval gate bypassed
      ENV['PATRA_APPROVAL_AUTORESUME'] = 'true'
      reset_run
      a_on = mk_approval.call(600)
      a_on.update_columns(status: 'approved')
      r = Approvals::AutoResume.execute!(a_on)
      ok!('F15 FLAG ON approve => executes once', r[:ok] == true && $FAKE.calls.count { |c| c[0] == :withdraw } == 1)
      ok!('F15 => GameAction appr_<id> success',
          GameAction.find_by(account_id: account.id, order_id: "appr_#{a_on.id}")&.status == 'success')
      ok!('F15 => cashout-group telegram recorded', cashout_tg.call)

      # DOUBLE-APPROVE: no-op
      r = Approvals::AutoResume.execute!(a_on)
      ok!('F15 DOUBLE-APPROVE => no-op, still exactly one withdraw',
          r[:already] == true && $FAKE.calls.count { |c| c[0] == :withdraw } == 1)

      # REJECT: never executes
      reset_run
      a_rej = mk_approval.call(600)
      a_rej.update_columns(status: 'rejected')
      r = Approvals::AutoResume.execute!(a_rej)
      ok!('F15 REJECT => never executes', r[:skipped] == :not_approved && !$FAKE.called?(:withdraw))

      # PANEL FAIL: telegram reports REAL remaining state + needs human
      reset_run(fail_withdraw: true)
      a_fail = mk_approval.call(700)
      a_fail.update_columns(status: 'approved')
      r = Approvals::AutoResume.execute!(a_fail)
      ok!('F15 PANEL FAIL => ok:false + telegram fired', r[:ok] == false && cashout_tg.call)
      ok!('F15 PANEL FAIL => action recorded failed (real state)',
          GameAction.find_by(account_id: account.id, order_id: "appr_#{a_fail.id}")&.status == 'failed')
    ensure
      if f15_saved_flag.nil?
        ENV.delete('PATRA_APPROVAL_AUTORESUME')
      else
        ENV['PATRA_APPROVAL_AUTORESUME'] = f15_saved_flag
      end
      begin
        GameAction.where(account_id: account.id, order_id: f15_approvals.map { |a| "appr_#{a.id}" }).delete_all
        f15_approvals.each(&:destroy)
        puts "[cleanup] removed #{f15_approvals.size} F15 approval(s) + their GameActions"
      rescue StandardError => e
        puts "[cleanup] F15 cleanup failed: #{e.class}: #{e.message}"
      end
    end
  end

  # ──────────────── TABA overnight fixes (BUG-1/2/3, 2026-06-10) ──────────────
  puts "\n[TABA-1 freeplay/bonus single-record]  (executor audits once, flag preserved)"
  reset_run; prime_contact!(contact, [src_slug])
  o_fp = orch(account, contact, [])
  r = o_fp.send(:execute_game_api, game_slug: src_slug, action: 'recharge',
                username: 'harnessuser1', amount: 5,
                metadata: { freeplay: true, source: 'bella_freeplay' })
  fp_actions = GameAction.where(contact_id: contact.id, action_type: 'load').to_a
  ok!('TABA-1 freeplay-style load => exactly ONE GameAction (no duplicate)', r[:success] == true && fp_actions.size == 1)
  ok!('TABA-1 the single record carries the freeplay flag',
      fp_actions.first&.metadata&.dig('freeplay').to_s == 'true')

  puts "\n[TABA-2 account-creation payment load dedup]  (F12 5th site)"
  # Happy path: create + load once.
  reset_run; prime_contact!(contact, [])
  contact.update!(custom_attributes: {
                    'patra_finance_logs' => [{
                      'id' => 'HARNESS_PAY_AC1', 'status' => 'confirmed', 'amount' => 30,
                      'recorded_at' => Time.current.iso8601, 'platform' => 'cashapp'
                    }]
                  })
  r1 = orch(account, contact, [{ 'role' => 'user', 'content' => 'create me an account' }])
         .send(:handle_account_creation_request, { intent: :request_account_creation, game_slug: src_slug })
  ok!('TABA-2 first create+load => recharge once, account created',
      $FAKE.calls.count { |c| c[0] == :recharge } == 1 && r1[:reply].to_s.include?('all set'))

  # True-race loser: the winner's success row sits on the unique index under the
  # deterministic base but is INVISIBLE to the legacy check-then-act guard
  # (different amount, empty metadata). Only the deterministic order_id stops
  # the second load - this exercises the new ac_order_id.nil? path.
  reset_run
  GameAction.where(contact_id: contact.id).delete_all
  contact.update!(custom_attributes: {
                    'patra_finance_logs' => [{
                      'id' => 'HARNESS_PAY_AC2', 'status' => 'confirmed', 'amount' => 40,
                      'recorded_at' => Time.current.iso8601, 'platform' => 'cashapp'
                    }]
                  })
  ac_base = orch(account, contact, []).send(:deterministic_payment_order_id, 'HARNESS_PAY_AC2')
  GameAction.create!(account_id: account.id, agent_game_id: ag.id, contact_id: contact.id,
                     action_type: 'load', order_id: ac_base, game_username: 'harnessuser1',
                     amount: 41, status: 'success', metadata: {}, executed_at: Time.current)
  r2 = orch(account, contact, [{ 'role' => 'user', 'content' => 'create me an account' }])
         .send(:handle_account_creation_request, { intent: :request_account_creation, game_slug: src_slug })
  ok!('TABA-2 race loser => NO recharge (deterministic id catches what check-then-act cannot)',
      !$FAKE.called?(:recharge))
  ok!('TABA-2 race loser reply says load already went through',
      r2[:reply].to_s.match?(/already went through/i))

  puts "\n[TABA-3 redeem-partial verb-adjacent amount]  (keep 30 in and cash out 50 => $50)"
  reset_run; prime_contact!(contact, [src_slug])
  r = orch(account, contact, [{ 'role' => 'user', 'content' => 'keep 30 in and cash out 50' }])
        .send(:handle_redeem_partial_replay, { intent: :redeem_partial_replay, game_slug: src_slug })
  wd = $FAKE.calls.find { |c| c[0] == :withdraw }
  ok!('TABA-3 withdraws the CASH OUT amount ($50), not the keep-in ($30)',
      wd && wd[1].to_f == 50.0)
  ok!('TABA-3 reply confirms the $50 cashout', r[:reply].to_s.include?('50'))

  # ==================== MONEYFLOWS RUN 1 (R1-R8, 2026-06-10) ==================
  puts "\n[R8 escalation-context helper]  (plain-language full-situation Telegram text)"
  reset_run
  r8_text = orch(account, contact, []).send(
    :escalation_context,
    wants: 'cash out $60 on juwa',
    done: 'verified balance $80',
    left: 'payout not sent',
    suggest: 'pay max $50, drop the rest',
    need: 'approve the payout'
  )
  ok!('R8 helper includes player intent', r8_text.include?('PLAYER WANTS: cash out $60 on juwa'))
  ok!('R8 helper includes what was already done', r8_text.include?('ALREADY DONE: verified balance $80'))
  ok!('R8 helper includes what is still left', r8_text.include?('STILL LEFT: payout not sent'))
  ok!('R8 helper includes Bella suggestion', r8_text.include?('BELLA SUGGESTS: pay max $50'))
  ok!('R8 helper includes what she needs from the human', r8_text.include?('NEEDS FROM HUMAN: approve the payout'))
  r8_min = orch(account, contact, []).send(:escalation_context, wants: 'load $20')
  ok!('R8 helper omits empty sections (no dangling labels)',
      r8_min == 'PLAYER WANTS: load $20')

  puts "\n[R1 transfer modes]  (off / deposit_only / whole, June 10 rules)"
  if t_src && t_tgt && t_src != t_tgt
    t_src_ag = actives.find { |a| a.game.slug == t_src }
    r1_plan = %({"source_game":"#{t_src}","cashout_amount":30,"loads":[{"game":"#{t_tgt}","amount":30}]})
    r1_msgs = [{ 'role' => 'user', 'content' => "move 30 from #{t_src} to #{t_tgt}" }]
    mk_dep = lambda do |amt, oid|
      GameAction.create!(account_id: account.id, agent_game_id: t_src_ag.id, contact_id: contact.id,
                         action_type: 'load', order_id: oid, game_username: 'harnessuser1',
                         amount: amt, status: 'success', metadata: {}, executed_at: Time.current)
    end

    # OFF -> decline before any panel call
    pref_row.update!(transfer_mode: 'off')
    reset_run(balance: 100.0); prime_contact!(contact, [t_src, t_tgt]); $DEEPSEEK = r1_plan
    r = orch(account, contact, r1_msgs).send(:handle_transfer_between_games, { intent: :transfer_between_games })
    ok!('R1 OFF => declined, no withdraw/recharge', !$FAKE.called?(:withdraw) && !$FAKE.called?(:recharge))
    ok!('R1 OFF => reply says transfers are off', r[:reply].to_s.match?(/don't do .*transfers/i))

    # DEPOSIT_ONLY happy: last deposit 30, balance 100, request 30 -> moves exactly 30
    pref_row.update!(transfer_mode: 'deposit_only')
    reset_run(balance: 100.0); prime_contact!(contact, [t_src, t_tgt]); $DEEPSEEK = r1_plan
    mk_dep.call(30, 'HARNESS_R1_DEP1')
    r = orch(account, contact, r1_msgs).send(:handle_transfer_between_games, { intent: :transfer_between_games })
    r1_wd = $FAKE.calls.find { |c| c[0] == :withdraw }
    ok!('R1 DEPOSIT_ONLY request==deposit => cashes out exactly the deposit ($30)', r1_wd && r1_wd[1].to_f == 30.0)
    ok!('R1 DEPOSIT_ONLY request==deposit => target load happened', $FAKE.called?(:recharge))

    # DEPOSIT_ONLY over-ask: deposit 30, balance 100, request 50 -> move NOTHING + real numbers
    pref_row.update!(transfer_mode: 'deposit_only')
    reset_run(balance: 100.0); prime_contact!(contact, [t_src, t_tgt])
    $DEEPSEEK = %({"source_game":"#{t_src}","cashout_amount":50,"loads":[{"game":"#{t_tgt}","amount":50}]})
    mk_dep.call(30, 'HARNESS_R1_DEP2')
    r = orch(account, contact, [{ 'role' => 'user', 'content' => "move 50 from #{t_src} to #{t_tgt}" }])
          .send(:handle_transfer_between_games, { intent: :transfer_between_games })
    ok!('R1 DEPOSIT_ONLY over-ask => moves NOTHING', !$FAKE.called?(:withdraw) && !$FAKE.called?(:recharge))
    ok!('R1 DEPOSIT_ONLY over-ask => states the real balance ($100)', r[:reply].to_s.include?('100'))

    # DEPOSIT_ONLY capped by balance: deposit 30 but only 20 left -> request 30 moves NOTHING
    pref_row.update!(transfer_mode: 'deposit_only')
    reset_run(balance: 20.0); prime_contact!(contact, [t_src, t_tgt]); $DEEPSEEK = r1_plan
    mk_dep.call(30, 'HARNESS_R1_DEP3')
    r = orch(account, contact, r1_msgs).send(:handle_transfer_between_games, { intent: :transfer_between_games })
    ok!('R1 DEPOSIT_ONLY deposit>balance => moveable capped at balance, over-ask moves NOTHING', !$FAKE.called?(:withdraw))
    ok!('R1 DEPOSIT_ONLY deposit>balance => states the real balance ($20)', r[:reply].to_s.include?('20'))

    # WHOLE: zero deposit history but balance 100 -> request 30 moves 30
    pref_row.update!(transfer_mode: 'whole')
    reset_run(balance: 100.0); prime_contact!(contact, [t_src, t_tgt]); $DEEPSEEK = r1_plan
    r = orch(account, contact, r1_msgs).send(:handle_transfer_between_games, { intent: :transfer_between_games })
    ok!('R1 WHOLE => full balance moveable, $30 request goes through', $FAKE.called?(:withdraw) && $FAKE.called?(:recharge))

    # NO USERNAME on source -> "haven't played that game with us"
    pref_row.update!(transfer_mode: 'whole')
    reset_run(balance: 100.0); prime_contact!(contact, [t_tgt]); $DEEPSEEK = r1_plan
    r = orch(account, contact, r1_msgs).send(:handle_transfer_between_games, { intent: :transfer_between_games })
    ok!("R1 NO SOURCE USERNAME => haven't-played reply + no money moved",
        r[:reply].to_s.match?(/haven't played/i) && !$FAKE.called?(:withdraw))

    # HALF-FAIL: cashout OK, load FAIL -> offer + R8 telegram with Remaining
    pref_row.update!(transfer_mode: 'whole')
    reset_run(balance: 100.0, fail_recharge: true); prime_contact!(contact, [t_src, t_tgt]); $DEEPSEEK = r1_plan
    r = orch(account, contact, r1_msgs).send(:handle_transfer_between_games, { intent: :transfer_between_games })
    ok!('R1 HALF-FAIL => reply offers another game or take the money',
        r[:reply].to_s.match?(/another game, or take the money/i))
    ok!('R1 HALF-FAIL => telegram carries R8 full context + Remaining',
        tg?('NEEDS FROM HUMAN') && tg?('Remaining'))
    pref_row.update!(transfer_mode: r1_saved_mode)
  else
    puts '  SKIPPED - need 2 self-resolving active agent_games'
  end

  puts "\n[R2 replay-from-balance never alters a load]  ($2 in game + load $10 => loads exactly $10)"
  reset_run(balance: 2.0); prime_contact!(contact, [src_slug])
  contact.update!(custom_attributes: contact.custom_attributes.merge(
    'patra_finance_logs' => [{
      'id' => 'HARNESS_PAY_R2', 'status' => 'confirmed', 'amount' => 10,
      'recorded_at' => Time.current.iso8601, 'platform' => 'cashapp'
    }]
  ))
  r = orch(account, contact, [{ 'role' => 'user', 'content' => 'load 10' }])
        .send(:handle_load_intent, { intent: :load, amount: 10, game_slug: src_slug, game_username: 'harnessuser1' })
  r2_rc = $FAKE.calls.find { |c| c[0] == :recharge }
  ok!('R2 leftover balance never subtracts/caps => recharge is EXACTLY $10', r2_rc && r2_rc[1].to_f == 10.0)
  ok!('R2 load succeeded with auto-load label', Array(r && r[:labels]).include?('auto-load'))

  puts "\n[R3 cashout min/max from LAST deposit]  (4x/10x of last dep, type-aware, real minimum stated)"
  r3_rule = GameRule.find_or_initialize_by(account_id: account.id, game_id: ag.game.id)
  r3_was_new = r3_rule.new_record?
  r3_snap = r3_was_new ? nil : r3_rule.attributes.dup
  r3_rule.assign_attributes(cashout_enabled: true, cashout_min_multiplier: 4, cashout_max_multiplier: 10,
                            cashout_max_amount: 250, cashout_min_amount: 10,
                            cashout_freeplay_multiplier: 5, cashout_freeplay_max: 50,
                            cashout_require_screenshot: false)
  r3_rule.save!
  mk_r3_load = lambda do |amt, oid, meta = {}, at = Time.current|
    GameAction.create!(account_id: account.id, agent_game_id: ag.id, contact_id: contact.id,
                       action_type: 'load', order_id: oid, game_username: 'harnessuser1',
                       amount: amt, status: 'success', metadata: meta,
                       executed_at: at, created_at: at, updated_at: at)
  end
  begin
    # Below the multiplier minimum: last deposit $5 -> min $20; ask $15 -> real minimum stated
    reset_run; prime_contact!(contact, [src_slug])
    mk_r3_load.call(5, 'HARNESS_R3_DEP1')
    r = orch(account, contact, [{ 'role' => 'user', 'content' => 'cash out 15' }])
          .send(:handle_cashout_intent, { intent: :cashout, game_slug: src_slug, amount: 15 })
    ok!('R3 below min (last dep $5, ask $15) => states the real minimum ($20)',
        r[:reply].to_s.match?(/min cashout on a \$5 deposit is \$20/i))

    # LAST deposit governs, not the lifetime sum: old $100 + latest $5 -> min still $20
    reset_run; prime_contact!(contact, [src_slug])
    mk_r3_load.call(100, 'HARNESS_R3_DEP2', {}, 2.hours.ago)
    mk_r3_load.call(5, 'HARNESS_R3_DEP3')
    r = orch(account, contact, [{ 'role' => 'user', 'content' => 'cash out 25' }])
          .send(:handle_cashout_intent, { intent: :cashout, game_slug: src_slug, amount: 25 })
    ok!('R3 LAST deposit governs (not sum) => $25 on a last $5 dep passes min, goes to cashier',
        r[:reply].to_s.match?(/processing/i))
    ok!('R3 pass => telegram cashout escalation fired', $TG.any?)

    # Type-aware: last load is FREEPLAY $5 -> freeplay fields (5x -> min $25)
    reset_run; prime_contact!(contact, [src_slug])
    mk_r3_load.call(5, 'HARNESS_R3_FP1', { freeplay: true })
    r = orch(account, contact, [{ 'role' => 'user', 'content' => 'cash out 15' }])
          .send(:handle_cashout_intent, { intent: :cashout, game_slug: src_slug, amount: 15 })
    ok!('R3 freeplay-typed last dep => freeplay multiplier rules ($5 fp -> min $25)',
        r[:reply].to_s.match?(/min cashout on a \$5 freeplay is \$25/i))
  ensure
    begin
      if r3_was_new
        r3_rule.destroy
      else
        r3_rule.update!(r3_snap.except('id', 'created_at', 'updated_at'))
      end
      puts '[cleanup] restored game_rule for R3'
    rescue StandardError => e
      puts "[cleanup] R3 game_rule restore failed: #{e.class}: #{e.message}"
    end
  end

  puts "\n[R4 over-max cashout modes]  (cash_whole default / pay_max_recharge)"
  r4_rule = GameRule.find_or_initialize_by(account_id: account.id, game_id: ag.game.id)
  r4_was_new = r4_rule.new_record?
  r4_snap = r4_was_new ? nil : r4_rule.attributes.dup
  r4_rule.assign_attributes(cashout_enabled: true, cashout_min_multiplier: 4, cashout_max_multiplier: 10,
                            cashout_max_amount: 250, cashout_min_amount: 10,
                            cashout_freeplay_multiplier: 5, cashout_freeplay_max: 50,
                            cashout_require_screenshot: false)
  r4_rule.save!
  r4_acct_attrs = (account.custom_attributes || {}).dup
  begin
    # DEFAULT cash_whole: last dep $5 -> max $50; ask $60 -> whole balance cashed, excess dropped
    account.update!(custom_attributes: r4_acct_attrs.reject { |k, _| k.to_s == 'cashout_overmax_mode' })
    reset_run; prime_contact!(contact, [src_slug])
    GameAction.create!(account_id: account.id, agent_game_id: ag.id, contact_id: contact.id,
                       action_type: 'load', order_id: 'HARNESS_R4_DEP1', game_username: 'harnessuser1',
                       amount: 5, status: 'success', metadata: {}, executed_at: Time.current)
    r = orch(account, contact, [{ 'role' => 'user', 'content' => 'cash out 60' }])
          .send(:handle_cashout_intent, { intent: :cashout, game_slug: src_slug, amount: 60 })
    ok!('R4 DEFAULT cash_whole => Bella says the game drops the over-limit',
        r[:reply].to_s.match?(/game drops anything over the max/i))
    ok!('R4 DEFAULT cash_whole => R8 telegram context fired', tg?('NEEDS FROM HUMAN'))
    ok!('R4 over-max moves no money itself', !$FAKE.called?(:withdraw) && !$FAKE.called?(:recharge))

    # pay_max_recharge: ask $60 over $50 max -> pay $50, recharge $10 back
    account.update!(custom_attributes: r4_acct_attrs.merge('cashout_overmax_mode' => 'pay_max_recharge'))
    reset_run; prime_contact!(contact, [src_slug])
    GameAction.create!(account_id: account.id, agent_game_id: ag.id, contact_id: contact.id,
                       action_type: 'load', order_id: 'HARNESS_R4_DEP2', game_username: 'harnessuser1',
                       amount: 5, status: 'success', metadata: {}, executed_at: Time.current)
    r = orch(account, contact, [{ 'role' => 'user', 'content' => 'cash out 60' }])
          .send(:handle_cashout_intent, { intent: :cashout, game_slug: src_slug, amount: 60 })
    ok!('R4 pay_max_recharge => Bella promises max $50 + $10 loaded back',
        r[:reply].to_s.match?(/get \$50/i) && r[:reply].to_s.match?(/extra \$10 back/i))
    ok!('R4 pay_max_recharge => R8 telegram says recharge the leftover', tg?('recharge $10 back'))
  ensure
    begin
      account.update!(custom_attributes: r4_acct_attrs)
      if r4_was_new
        r4_rule.destroy
      else
        r4_rule.update!(r4_snap.except('id', 'created_at', 'updated_at'))
      end
      puts '[cleanup] restored account attrs + game_rule for R4'
    rescue StandardError => e
      puts "[cleanup] R4 restore failed: #{e.class}: #{e.message}"
    end
  end

  puts "\n[R5 partial keep-in recorded as new deposit]  (cash out 30, keep 20 -> 20 is the new last deposit)"
  reset_run; prime_contact!(contact, [src_slug])
  r = orch(account, contact, [{ 'role' => 'user', 'content' => 'cash out 30 and keep 20 in' }])
        .send(:handle_redeem_partial_replay, { intent: :redeem_partial_replay, game_slug: src_slug })
  r5_wd = $FAKE.calls.find { |c| c[0] == :withdraw }
  ok!('R5 cashes out the verb-adjacent $30 (TABA-3 semantics stay green)', r5_wd && r5_wd[1].to_f == 30.0)
  r5_keep = GameAction.where(contact_id: contact.id, action_type: 'load', status: 'success')
                      .where("metadata->>'keep_in_from_cashout' = 'true'").order(created_at: :desc).first
  ok!('R5 kept $20 recorded as a NEW deposit (load/success with keep-in flag)',
      r5_keep && r5_keep.amount.to_f == 20.0)
  ok!('R5 telegram labels it RELOAD/keep-in-from-cashout, not a fresh deposit',
      tg?('RELOAD (keep-in-from-cashout)'))
  r5_last = orch(account, contact, []).send(:last_deposit_for_cashout, src_slug)
  ok!('R5 keep-in drives next rules => it is now the LAST deposit ($20, type deposit)',
      r5_last && r5_last[:amount] == 20.0 && r5_last[:type] == 'deposit')

  reset_run; prime_contact!(contact, [src_slug])
  orch(account, contact, [{ 'role' => 'user', 'content' => 'cash out 20 and keep the rest' }])
    .send(:handle_redeem_partial_replay, { intent: :redeem_partial_replay, game_slug: src_slug })
  ok!('R5 "keep the rest" (no number) => nothing recorded',
      !GameAction.where(contact_id: contact.id).where("metadata->>'keep_in_from_cashout' = 'true'").exists?)

  puts "\n[R6 account creation choice + failure ladder]"
  # R6a LOCK: create on request with NO payment - no deposit gate ever
  reset_run; prime_contact!(contact, [])
  r = orch(account, contact, [{ 'role' => 'user', 'content' => 'set me up on ' + src_slug }])
        .send(:handle_account_creation_request, { intent: :request_account_creation, game_slug: src_slug })
  ok!('R6a no-payment create => account created, NO deposit gate', $FAKE.called?(:add_user) && r[:reply].to_s.include?('username'))
  ok!('R6a => payment handle offered AFTER creation', Array(r[:labels]).include?('awaiting-payment'))

  # R6b: existing account + asks to create -> ASK use-old vs make-new
  reset_run; prime_contact!(contact, [src_slug])
  contact.update!(custom_attributes: contact.custom_attributes.merge("game_password_#{src_slug}" => 'oldpass123'))
  r = orch(account, contact, [{ 'role' => 'user', 'content' => 'make me an account' }])
        .send(:handle_account_creation_request, { intent: :request_account_creation, game_slug: src_slug })
  ok!('R6b existing account + create ask => asks use-old or make-new, creates nothing yet',
      r[:reply].to_s.match?(/use that one, or make a new one/i) && !$FAKE.called?(:add_user))
  ok!('R6b => choice flag stored on contact', contact.reload.custom_attributes['pending_account_choice'].present?)

  # use-old -> resend stored creds, no new account
  r = orch(account, contact, []).send(:resolve_pending_account_choice, 'use that one',
                                      contact.custom_attributes['pending_account_choice'])
  ok!('R6b use-old => creds resent, no new account',
      r && r[:reply].to_s.include?('harnessuser1') && r[:reply].to_s.include?('oldpass123') && !$FAKE.called?(:add_user))
  ok!('R6b choice flag cleared after answer', contact.reload.custom_attributes['pending_account_choice'].blank?)

  # make-new -> fresh account, vault creds swapped (old stays on the panel)
  reset_run; prime_contact!(contact, [src_slug])
  contact.update!(custom_attributes: contact.custom_attributes.merge("game_password_#{src_slug}" => 'oldpass123'))
  orch(account, contact, [{ 'role' => 'user', 'content' => 'make me an account' }])
    .send(:handle_account_creation_request, { intent: :request_account_creation, game_slug: src_slug })
  r = orch(account, contact, []).send(:resolve_pending_account_choice, 'make a new one',
                                      contact.reload.custom_attributes['pending_account_choice'])
  ok!('R6b make-new => fresh account created, vault creds swapped',
      $FAKE.called?(:add_user) && contact.reload.custom_attributes["game_username_#{src_slug}"] != 'harnessuser1')

  # R6c: reset fails -> ladder falls to create-new (no dead-end)
  reset_run(fail_reset_player_password: true); prime_contact!(contact, [src_slug])
  r = orch(account, contact, []).send(:handle_reset_password_intent, { intent: :reset_password, game_slug: src_slug })
  ok!('R6c reset fails => ladder falls to create-new (no dead-end)',
      $FAKE.called?(:add_user) && r[:reply].to_s.match?(/new .*account|all set/i))

  # R6c: reset fails AND create fails -> rungs 4-5: suggest different game + Telegram human
  reset_run(fail_reset_player_password: true, fail_add_user: true); prime_contact!(contact, [src_slug])
  r = orch(account, contact, []).send(:handle_reset_password_intent, { intent: :reset_password, game_slug: src_slug })
  ok!('R6c ladder end => needs-human + R8 telegram context',
      Array(r[:labels]).include?('needs-human') && tg?('NEEDS FROM HUMAN'))
  ok!('R6c ladder end => reply suggests a path, not a silent dead-end',
      r[:reply].to_s.match?(/instead|teammate/i))

  # R6c: reissue create-fail -> ladder end (existing reissue FAIL assertions stay green)
  reset_run(fail_add_user: true); prime_contact!(contact, [src_slug])
  r = orch(account, contact, []).send(:handle_new_account_reissue, { intent: :new_account_reissue, game_slug: src_slug })
  ok!('R6c reissue create-fail => ladder-exhausted + R8 telegram',
      Array(r[:labels]).include?('ladder-exhausted') && tg?('NEEDS FROM HUMAN'))

  puts "\n[R7 auto-load dollar threshold]  (default 200; over -> hold + approval, NO load)"
  # over threshold: $250 verified deposit, default threshold 200 -> NO recharge
  account.update!(custom_attributes: (account.custom_attributes || {}).reject { |k, _| k.to_s == 'auto_load_threshold' })
  reset_run; prime_contact!(contact, [src_slug])
  contact.update!(custom_attributes: contact.custom_attributes.merge(
    'patra_finance_logs' => [{ 'id' => 'HARNESS_PAY_R7A', 'status' => 'confirmed', 'amount' => 250,
                               'recorded_at' => Time.current.iso8601, 'platform' => 'cashapp' }]
  ))
  r = orch(account, contact, [{ 'role' => 'user', 'content' => 'load 250' }])
        .send(:handle_load_intent, { intent: :load, amount: 250, game_slug: src_slug, game_username: 'harnessuser1' })
  ok!('R7 over-threshold (default $200) => NO load executed', !$FAKE.called?(:recharge))
  ok!('R7 over-threshold => needs-human + hold labels',
      Array(r[:labels]).include?('needs-human') && Array(r[:labels]).include?('over-threshold-hold'))
  ok!('R7 over-threshold => R8 telegram escalation', tg?('NEEDS FROM HUMAN'))
  r7_appr = ApprovalRequest.where(account_id: account.id, action_type: 'load', status: 'pending')
                           .where("metadata->>'source' = 'bella_over_threshold'")
  ok!('R7 over-threshold => pending load ApprovalRequest created (F15 record type)', r7_appr.exists?)
  r7_appr.delete_all

  # at threshold: $200 exactly -> auto-loads as before
  reset_run; prime_contact!(contact, [src_slug])
  contact.update!(custom_attributes: contact.custom_attributes.merge(
    'patra_finance_logs' => [{ 'id' => 'HARNESS_PAY_R7B', 'status' => 'confirmed', 'amount' => 200,
                               'recorded_at' => Time.current.iso8601, 'platform' => 'cashapp' }]
  ))
  r = orch(account, contact, [{ 'role' => 'user', 'content' => 'load 200' }])
        .send(:handle_load_intent, { intent: :load, amount: 200, game_slug: src_slug, game_username: 'harnessuser1' })
  ok!('R7 at threshold ($200 = limit) => auto-loads as before',
      $FAKE.called?(:recharge) && Array(r && r[:labels]).include?('auto-load'))

  # custom threshold via account custom_attributes: $50 -> a $60 deposit is held
  account.update!(custom_attributes: (account.custom_attributes || {}).merge('auto_load_threshold' => 50))
  reset_run; prime_contact!(contact, [src_slug])
  contact.update!(custom_attributes: contact.custom_attributes.merge(
    'patra_finance_logs' => [{ 'id' => 'HARNESS_PAY_R7C', 'status' => 'confirmed', 'amount' => 60,
                               'recorded_at' => Time.current.iso8601, 'platform' => 'cashapp' }]
  ))
  r = orch(account, contact, [{ 'role' => 'user', 'content' => 'load 60' }])
        .send(:handle_load_intent, { intent: :load, amount: 60, game_slug: src_slug, game_username: 'harnessuser1' })
  ok!('R7 custom threshold ($50) => $60 held', !$FAKE.called?(:recharge) && Array(r[:labels]).include?('over-threshold-hold'))
  ApprovalRequest.where(account_id: account.id, action_type: 'load', status: 'pending')
                 .where("metadata->>'source' = 'bella_over_threshold'").delete_all
  account.update!(custom_attributes: (account.custom_attributes || {})
    .reject { |k, _| k.to_s == 'auto_load_threshold' }.merge('auto_load_threshold' => 1_000_000))

  # F12 coverage at the username_provided site: a race loser must NOT double-load
  reset_run; prime_contact!(contact, [src_slug])
  contact.update!(custom_attributes: contact.custom_attributes.merge(
    'patra_finance_logs' => [{ 'id' => 'HARNESS_PAY_R7D', 'status' => 'confirmed', 'amount' => 45,
                               'recorded_at' => Time.current.iso8601, 'platform' => 'cashapp' }]
  ))
  r7_base = orch(account, contact, []).send(:deterministic_payment_order_id, 'HARNESS_PAY_R7D')
  GameAction.create!(account_id: account.id, agent_game_id: ag.id, contact_id: contact.id,
                     action_type: 'load', order_id: r7_base, game_username: 'harnessuser1',
                     amount: 46, status: 'success', metadata: {}, executed_at: Time.current)
  r = orch(account, contact, [{ 'role' => 'user', 'content' => 'harnessuser1' }])
        .send(:handle_username_provided, { intent: :username_provided, game_slug: src_slug, game_username: 'harnessuser1' })
  ok!('R7/F12 username_provided race loser => NO recharge (deterministic id holds)', !$FAKE.called?(:recharge))

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
  begin
    account.update!(custom_attributes: r7_acct_saved) if defined?(r7_acct_saved) && r7_acct_saved
    puts '[cleanup] restored account custom_attributes'
  rescue StandardError => e
    puts "[cleanup] account custom_attributes restore failed: #{e.class}: #{e.message}"
  end
  begin
    if defined?(pref_row) && pref_row && pref_row.transfer_mode != r1_saved_mode
      pref_row.update!(transfer_mode: r1_saved_mode)
      puts '[cleanup] restored reply_preference transfer_mode'
    end
  rescue StandardError => e
    puts "[cleanup] transfer_mode restore failed: #{e.class}: #{e.message}"
  end
  restore_stubs
  puts '[cleanup] restored stubs'
end
