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

# MONEYFLOWS2: stub IMAP refresh (instance method) - restored in ensure.
if defined?(Payments::EmailConfirmationService)
  Payments::EmailConfirmationService.class_eval do
    unless method_defined?(:orig_check_all_harness)
      alias_method :orig_check_all_harness, :check_all
      def check_all
        { checked: 0, confirmed: 0 }
      end
    end
  end
end

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

# MEGA-AUDIT confirm-gate pin (June 11, assertions unchanged): with real
# conversations the confirm_before_load (:346) / confirm_before_cashout (:1288)
# gates become reachable — under conversation:nil they were silently skipped
# (the nil deref raised inside the gate's own rescue). Account 2 ships
# confirm_before_cashout=true (migration default), which would turn the asserted
# "processing" cashout replies (R3 pass case) into "confirm cashout? (yes/no)"
# asks. Pin BOTH false for the whole run — same global snapshot+restore pattern
# as the R7 auto_load_threshold pin below; restored in ensure.
cg_saved = {}
%i[confirm_before_load confirm_before_cashout].each do |k|
  cg_saved[k] = pref_row.public_send(k) if pref_row.respond_to?(k)
end
pref_row.update!(cg_saved.transform_values { false }) if cg_saved.any?

# MEGA-AUDIT referral pin (whole run; G3 re-pins for its section): account
# creations in R6/TABA-2 fire link_referred_on_account_creation, which links
# ANY account-wide pending referral to the throwaway contact (orchestrator
# :4473-4489 - PROD finding, see PATRA_MEGA_AUDIT_LOG) and, with
# referral_enabled true, would auto-pay the real referrer through the stubbed
# panel, leaving GameActions on a REAL contact the cleanup never touches.
# Pin false; restored in ensure. Referred-side links are unlinked in ensure.
ref_en_saved = pref_row.respond_to?(:referral_enabled) ? pref_row.referral_enabled : nil
pref_row.update!(referral_enabled: false) if pref_row.respond_to?(:referral_enabled)

# MONEYFLOWS R7 fixture pin (assertions unchanged - see log D6): the legacy F13
# scenario loads $999 with the per-agent cap unset; pin the new dollar threshold
# high so F13 keeps testing the per-agent cap. R7 scenarios set their own values.
r7_acct_saved = (account.custom_attributes || {}).dup
# MEGA-AUDIT: also strip live generosity keys for the run (restored via
# r7_acct_saved in ensure). compute_auto_bonus / freeplay / referral settings
# fall through to account custom_attributes; stray live values would silently
# drift the exact-amount assertions in R2/S1/S3/G1/G3 (e.g. a live
# bonus_percent turns S3's $30 recharge into $30+x). G2/G3 scenarios set
# their own values per case.
GENEROSITY_PIN_KEYS = %w[bonus_percent first_deposit_bonus_percent bonus_min_deposit
                         freeplay_amount freeplay_daily_limit_per_player signup_bonus_amount
                         referral_reward_mode referral_percent referral_fixed_amount
                         referral_min_deposit].freeze
account.update!(custom_attributes: r7_acct_saved
  .reject { |k, _| GENEROSITY_PIN_KEYS.include?(k.to_s) }
  .merge('auto_load_threshold' => 1_000_000))

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

# MEGA-AUDIT (June 11): every orchestrator now gets a FRESH REAL conversation.
# handle_cashout_intent (:1158) and handle_load_bonus (:1003) deref
# conversation.contact unguarded — the old conversation:nil crashed the June 10
# Render run at the first R3 cashout case. Fresh per call so additional_attributes
# (pending_cashout, load_confirmed, payment_match_misses...) never leak between
# cases; pass convo: to deliberately SHARE one conversation across calls that
# model a single ongoing thread (S3 miss counter). Every conversation created
# here is tracked and destroyed in the ensure block BEFORE the contact.
def harness_inbox(account)
  $HARNESS_INBOX ||= account.inboxes.detect { |i| i.channel_type == 'Channel::Api' } ||
                     account.inboxes.order(:id).first
end
def new_harness_conversation(account, contact)
  inbox = harness_inbox(account)
  abort '[harness] account has no inbox — cannot build real conversations' unless inbox
  ci = ContactInbox.find_by(contact_id: contact.id, inbox_id: inbox.id) ||
       ContactInbox.create!(contact: contact, inbox: inbox, source_id: SecureRandom.uuid)
  Conversation.create!(account: account, inbox: inbox, contact: contact, contact_inbox: ci)
end
def orch(account, contact, msgs, convo: nil)
  convo ||= new_harness_conversation(account, contact)
  Games::ConversationOrchestrator.new(account: account, contact: contact, conversation: convo, messages: msgs)
end
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

  # ==================== MONEYFLOWS RUN 2 (S1-S3, 2026-06-10) ==================
  puts "\n[S1 status_check]  (re-verify, finish undone work via guards, real-state replies)"
  # (c) undone verifiable work -> completed through the NORMAL load path (guards apply)
  reset_run; prime_contact!(contact, [src_slug])
  contact.update!(custom_attributes: contact.custom_attributes.merge(
    'patra_finance_logs' => [{ 'id' => 'HARNESS_PAY_S1A', 'status' => 'confirmed', 'amount' => 25,
                               'recorded_at' => Time.current.iso8601, 'platform' => 'cashapp' }]
  ))
  s1_msgs = [{ 'role' => 'user', 'content' => 'did my load go through?' }]
  r = orch(account, contact, s1_msgs).send(:handle_status_check, { intent: :status_check, game_slug: src_slug })
  s1_rc = $FAKE.calls.find { |c| c[0] == :recharge }
  ok!('S1 undone work => completed via the normal load path ($25 recharge)', s1_rc && s1_rc[1].to_f == 25.0)
  ok!('S1 undone work => carries status-check + auto-load labels',
      Array(r[:labels]).include?('status-check') && Array(r[:labels]).include?('auto-load'))

  # (c) re-ask after completion -> guard no-op, NO second execution, real-state reply
  reset_run   # keep the GameAction + Loaded log entry
  r = orch(account, contact, s1_msgs).send(:handle_status_check, { intent: :status_check, game_slug: src_slug })
  ok!('S1 re-ask after done => NO re-execution (guard no-op)', !$FAKE.called?(:recharge))
  ok!('S1 re-ask => reply states the REAL state (went through)', r[:reply].to_s.match?(/went through|already went/i))

  # (b) unresolved load ask in the window, no payment -> normal path asks for payment
  reset_run; prime_contact!(contact, [src_slug])
  r = orch(account, contact, [{ 'role' => 'user', 'content' => 'load 35' },
                              { 'role' => 'user', 'content' => 'is it done yet?' }])
        .send(:handle_status_check, { intent: :status_check, game_slug: src_slug })
  ok!('S1 unresolved ask without payment => real state: asks for the payment, no load',
      !$FAKE.called?(:recharge) && r[:reply].to_s.match?(/send/i))

  # (d) nothing pending + nothing recent -> ask what they need
  reset_run; prime_contact!(contact, [src_slug])
  r = orch(account, contact, [{ 'role' => 'user', 'content' => 'is it done?' }])
        .send(:handle_status_check, { intent: :status_check, game_slug: src_slug })
  ok!('S1 nothing pending => all-clear + asks what they need', r[:reply].to_s.match?(/all clear.*what do you need/i))

  # (e) failed last action -> real-state reply + R8 escalation
  reset_run; prime_contact!(contact, [src_slug])
  GameAction.create!(account_id: account.id, agent_game_id: ag.id, contact_id: contact.id,
                     action_type: 'load', order_id: 'HARNESS_S1_FAIL', game_username: 'harnessuser1',
                     amount: 15, status: 'failed', metadata: {}, executed_at: Time.current)
  r = orch(account, contact, [{ 'role' => 'user', 'content' => 'did it work?' }])
        .send(:handle_status_check, { intent: :status_check, game_slug: src_slug })
  ok!('S1 failed action => honest reply + cashier label',
      r[:reply].to_s.match?(/hit a snag|didn't go through/i) && Array(r[:labels]).include?('cashier-action-needed'))
  ok!('S1 failed action => R8 telegram context', tg?('NEEDS FROM HUMAN'))

  puts "\n[S2 balance_check]  (live balance, no invented numbers, signup offer, classification)"
  # (b) live balance reply
  reset_run(balance: 75.0); prime_contact!(contact, [src_slug])
  r = orch(account, contact, [{ 'role' => 'user', 'content' => 'how much i got?' }])
        .send(:handle_balance_check, { intent: :balance_check, game_slug: src_slug })
  ok!('S2 live balance => states the REAL number ($75)', r[:reply].to_s.include?('75'))
  ok!('S2 live balance => no telegram needed', $TG.empty?)

  # (b) API error => no invented number + R8 escalation
  reset_run(balance: nil); prime_contact!(contact, [src_slug])
  r = orch(account, contact, [{ 'role' => 'user', 'content' => 'check my balance' }])
        .send(:handle_balance_check, { intent: :balance_check, game_slug: src_slug })
  ok!('S2 API error => NO number invented', !r[:reply].to_s.match?(/\$\d/))
  ok!('S2 API error => R8 escalation fired + cashier label',
      tg?('NEEDS FROM HUMAN') && Array(r[:labels]).include?('cashier-action-needed'))

  # (c) no username => signup offer routed into the existing create path
  reset_run; prime_contact!(contact, [])
  r = orch(account, contact, [{ 'role' => 'user', 'content' => 'whats my balance on ' + src_slug }])
        .send(:handle_balance_check, { intent: :balance_check, game_slug: src_slug })
  ok!('S2 no account => offers signup, no balance call',
      r[:reply].to_s.match?(/don't have a .* account .* want me to set one up/i) && !$FAKE.called?(:user_balance))
  s2_pending = contact.reload.custom_attributes['pending_transfer_create']
  ok!('S2 no account => pending create flag stored (existing yes/no path)', s2_pending.present?)
  r = orch(account, contact, []).send(:complete_pending_transfer_create, s2_pending)
  ok!('S2 saying yes => account actually created via the existing path',
      $FAKE.called?(:add_user) && r[:reply].to_s.include?('username'))

  # (a) ambiguity: two usernames, no explicit game => asks which game
  if t_src && t_tgt && t_src != t_tgt
    reset_run; prime_contact!(contact, [t_src, t_tgt])
    r = orch(account, contact, [{ 'role' => 'user', 'content' => 'how much i got?' }])
          .send(:handle_balance_check, { intent: :balance_check })
    ok!('S2 two accounts, no game named => asks which game', r[:reply].to_s.match?(/which game/i))
  else
    puts '  S2 ambiguity case SKIPPED - need 2 self-resolving active agent_games'
  end

  # (a) cashout-limit question => R3 math with real numbers
  s2_rule = GameRule.find_or_initialize_by(account_id: account.id, game_id: ag.game.id)
  s2_was_new = s2_rule.new_record?
  s2_snap = s2_was_new ? nil : s2_rule.attributes.dup
  s2_rule.assign_attributes(cashout_enabled: true, cashout_min_multiplier: 4, cashout_max_multiplier: 10,
                            cashout_max_amount: 250, cashout_min_amount: 10,
                            cashout_freeplay_multiplier: 5, cashout_freeplay_max: 50,
                            cashout_require_screenshot: false)
  s2_rule.save!
  begin
    reset_run; prime_contact!(contact, [src_slug])
    GameAction.create!(account_id: account.id, agent_game_id: ag.id, contact_id: contact.id,
                       action_type: 'load', order_id: 'HARNESS_S2_DEP', game_username: 'harnessuser1',
                       amount: 5, status: 'success', metadata: {}, executed_at: Time.current)
    r = orch(account, contact, [{ 'role' => 'user', 'content' => 'how much can i cash out?' }])
          .send(:handle_balance_check, { intent: :balance_check, game_slug: src_slug })
    ok!('S2 cashout-limit ask => classified + answers with R3 real numbers (min $20, max $50)',
        r[:reply].to_s.match?(/min cashout \$20.*max \$50/i))
    ok!('S2 cashout-limit ask => no live balance call needed', !$FAKE.called?(:user_balance))
  ensure
    begin
      if s2_was_new
        s2_rule.destroy
      else
        s2_rule.update!(s2_snap.except('id', 'created_at', 'updated_at'))
      end
      puts '[cleanup] restored game_rule for S2'
    rescue StandardError => e
      puts "[cleanup] S2 game_rule restore failed: #{e.class}: #{e.message}"
    end
  end

  puts "\n[S3 payment_sent]  (email match -> load; sender memory; 2 misses then escalate; never load unverified)"
  s3_entry = lambda do |over = {}|
    { 'id' => "HARNESS_PAY_S3_#{over['id'] || 'X'}", 'status' => 'Email Verified', 'amount' => 30,
      'recorded_at' => Time.current.iso8601, 'platform' => 'cashapp',
      'email_confirmed' => true, 'email_amount' => 30, 'email_sender_name' => 'John Doe',
      'email_date' => Time.current.iso8601 }.merge(over)
  end

  # (a)+(c) full match -> auto-load through the normal path, name remembered
  reset_run; prime_contact!(contact, [src_slug])
  contact.update!(custom_attributes: contact.custom_attributes.merge('patra_finance_logs' => [s3_entry.call('id' => 'A')]))
  r = orch(account, contact, [{ 'role' => 'user', 'content' => 'just sent 30 from John Doe' }])
        .send(:handle_payment_sent_confirmation, { intent: :payment_sent_confirmation, game_slug: src_slug })
  s3_rc = $FAKE.calls.find { |c| c[0] == :recharge }
  ok!('S3 verified email match => auto-loads $30 via the normal path', s3_rc && s3_rc[1].to_f == 30.0)
  ok!('S3 match => sender name remembered on contact',
      contact.reload.custom_attributes['payment_sender_name'].to_s.downcase.include?('john'))

  # (c) same payment again -> already loaded, refuse, no second load
  reset_run
  r = orch(account, contact, [{ 'role' => 'user', 'content' => 'i sent 30 from John Doe, load it' }])
        .send(:handle_payment_sent_confirmation, { intent: :payment_sent_confirmation, game_slug: src_slug })
  ok!('S3 already-loaded => refused, NO second load',
      !$FAKE.called?(:recharge) && r[:reply].to_s.match?(/already loaded/i))

  # (b) remembered sender skips the name question entirely
  reset_run; prime_contact!(contact, [src_slug])
  contact.update!(custom_attributes: contact.custom_attributes.merge(
    'payment_sender_name' => 'John Doe',
    'patra_finance_logs' => [s3_entry.call('id' => 'B', 'amount' => 40, 'email_amount' => 40)]
  ))
  r = orch(account, contact, [{ 'role' => 'user', 'content' => 'i just sent it' }])
        .send(:handle_payment_sent_confirmation, { intent: :payment_sent_confirmation, game_slug: src_slug })
  ok!('S3 remembered sender => no name question, loads the $40',
      !r[:reply].to_s.match?(/what name/i) && $FAKE.calls.any? { |c| c[0] == :recharge && c[1].to_f == 40.0 })

  # no name anywhere -> asks for name + screenshot, NOT a miss, never loads
  # MEGA-AUDIT: with a real conversation the miss counter lives on
  # conversation.additional_attributes (orchestrator:2629, contact only as the
  # nil-conversation fallback) — assert BOTH locations stay zero.
  reset_run; prime_contact!(contact, [src_slug])
  s3_nn_convo = new_harness_conversation(account, contact)
  r = orch(account, contact, [{ 'role' => 'user', 'content' => 'i sent it' }], convo: s3_nn_convo)
        .send(:handle_payment_sent_confirmation, { intent: :payment_sent_confirmation, game_slug: src_slug })
  ok!('S3 no name known => asks for name + screenshot, no load',
      r[:reply].to_s.match?(/what name/i) && !$FAKE.called?(:recharge))
  ok!('S3 asking for the name is NOT a miss',
      contact.reload.custom_attributes['payment_match_misses'].to_i.zero? &&
      (s3_nn_convo.reload.additional_attributes || {})['payment_match_misses'].to_i.zero?)

  # (d) no matching email: miss 1, miss 2, then 3rd insist -> escalate. NEVER loads.
  # MEGA-AUDIT: ONE shared conversation across the 3 calls — the miss counter is
  # per-conversation now; fresh-per-call conversations would reset it each turn.
  reset_run; prime_contact!(contact, [src_slug])
  s3_miss_msgs = [{ 'role' => 'user', 'content' => 'i sent 25 from John Doe' }]
  s3_miss_convo = new_harness_conversation(account, contact)
  r1m = orch(account, contact, s3_miss_msgs, convo: s3_miss_convo).send(:handle_payment_sent_confirmation, { intent: :payment_sent_confirmation, game_slug: src_slug })
  r2m = orch(account, contact, s3_miss_msgs, convo: s3_miss_convo).send(:handle_payment_sent_confirmation, { intent: :payment_sent_confirmation, game_slug: src_slug })
  ok!('S3 misses 1+2 => honest not-landed replies, no telegram yet',
      r1m[:reply].to_s.match?(/don't see it/i) && r2m[:reply].to_s.match?(/don't see it/i) && $TG.empty?)
  r3m = orch(account, contact, s3_miss_msgs, convo: s3_miss_convo).send(:handle_payment_sent_confirmation, { intent: :payment_sent_confirmation, game_slug: src_slug })
  ok!('S3 3rd insist => escalates with R8 context + needs-human',
      Array(r3m[:labels]).include?('needs-human') && tg?('NEEDS FROM HUMAN'))
  ok!('S3 unverified => NEVER loaded anything across all attempts', !$FAKE.called?(:recharge))

  # ==================== MONEYFLOWS RUN 3 (G1-G4, 2026-06-10) ==================
  puts "\n[G1 freeplay generosity pattern]  (override first, default escalates with the case)"
  g1_rule = GameRule.find_or_initialize_by(account_id: account.id, game_id: ag.game.id)
  g1_was_new = g1_rule.new_record?
  g1_snap = g1_was_new ? nil : g1_rule.attributes.dup
  g1_rule.assign_attributes(freeplay_enabled: false)
  g1_rule.save!
  g1_flag_saved = ENV['PATRA_APPROVAL_AUTORESUME']
  g1_approvals = ApprovalRequest.where(account_id: account.id, action_type: 'load')
                                .where("metadata->>'source' = 'bella_freeplay'")
  begin
    # override approve -> loads the configured amount now, freeplay flag set
    reset_run; prime_contact!(contact, [src_slug])
    contact.update!(custom_attributes: contact.custom_attributes.merge('freeplay_auto' => 'approve'))
    r = orch(account, contact, [{ 'role' => 'user', 'content' => 'can i get freeplay?' }])
          .send(:handle_load_freeplay, { intent: :load_freeplay, game_slug: src_slug })
    g1_fp = GameAction.where(contact_id: contact.id, action_type: 'load', status: 'success')
                      .where("metadata->>'freeplay' = 'true'").order(created_at: :desc).first
    ok!('G1 override approve => loads $5 freeplay now (flag set, single record)',
        $FAKE.called?(:recharge) && g1_fp && g1_fp.amount.to_f == 5.0)
    ok!('G1 decision logged for analysis (given)',
        Array(contact.reload.custom_attributes['patra_generosity_log']).any? { |e| e.is_a?(Hash) && e['decision'] == 'given' })

    # daily limit respected on EVERY path (even override approve)
    reset_run   # keep the freeplay GameAction just created
    r = orch(account, contact, [{ 'role' => 'user', 'content' => 'more freeplay?' }])
          .send(:handle_load_freeplay, { intent: :load_freeplay, game_slug: src_slug })
    ok!('G1 daily limit => second freeplay today declined, no load',
        !$FAKE.called?(:recharge) && r[:reply].to_s.match?(/already got your freeplay today/i))

    # override deny -> polite decline
    reset_run; prime_contact!(contact, [src_slug])
    contact.update!(custom_attributes: contact.custom_attributes.merge('freeplay_auto' => 'deny'))
    r = orch(account, contact, [{ 'role' => 'user', 'content' => 'freeplay?' }])
          .send(:handle_load_freeplay, { intent: :load_freeplay, game_slug: src_slug })
    ok!('G1 override deny => polite decline, no load',
        !$FAKE.called?(:recharge) && r[:reply].to_s.match?(/maxed out on freeplay/i))

    # DEFAULT (no override, GameRule freeplay off) -> full case + pending approval
    reset_run; prime_contact!(contact, [src_slug])
    GameAction.create!(account_id: account.id, agent_game_id: ag.id, contact_id: contact.id,
                       action_type: 'load', order_id: 'HARNESS_G1_DEP', game_username: 'harnessuser1',
                       amount: 50, status: 'success', metadata: {}, executed_at: Time.current)
    r = orch(account, contact, [{ 'role' => 'user', 'content' => 'any freeplay for me?' }])
          .send(:handle_load_freeplay, { intent: :load_freeplay, game_slug: src_slug })
    ok!('G1 default => no money moved, needs-human pending reply',
        !$FAKE.called?(:recharge) && Array(r[:labels]).include?('needs-human'))
    ok!('G1 default => case carries WHY GIVE / WHY NOT / counts',
        tg?('WHY GIVE') && tg?('WHY NOT') && tg?('lifetime deposits $50'))
    g1_appr = g1_approvals.where(status: 'pending').order(:id).last
    ok!('G1 default => pending ApprovalRequest (source bella_freeplay)',
        g1_appr.present? && g1_appr.amount.to_f == 5.0)

    # operator approve -> loads exactly once via the normal path (AutoResume)
    ENV['PATRA_APPROVAL_AUTORESUME'] = 'true'
    reset_run
    g1_appr.update_columns(status: 'approved')
    res = Approvals::AutoResume.execute!(g1_appr)
    g1_loaded = GameAction.find_by(account_id: account.id, order_id: "appr_#{g1_appr.id}")
    ok!('G1 operator approve => freeplay loads once via the normal path',
        res[:ok] == true && $FAKE.calls.count { |c| c[0] == :recharge } == 1)
    ok!('G1 approved load carries the freeplay flag (R3 typing holds)',
        g1_loaded && g1_loaded.metadata['freeplay'].to_s == 'true' && g1_loaded.amount.to_f == 5.0)
    ENV.delete('PATRA_APPROVAL_AUTORESUME')

    # operator reject -> the next ask declines politely, no re-escalation
    reset_run
    GameAction.where(contact_id: contact.id).delete_all
    orch(account, contact, [{ 'role' => 'user', 'content' => 'freeplay pls' }])
      .send(:handle_load_freeplay, { intent: :load_freeplay, game_slug: src_slug })
    g1_appr2 = g1_approvals.where(status: 'pending').order(:id).last
    g1_appr2&.update_columns(status: 'rejected', updated_at: Time.current)
    reset_run
    r = orch(account, contact, [{ 'role' => 'user', 'content' => 'freeplay pls' }])
          .send(:handle_load_freeplay, { intent: :load_freeplay, game_slug: src_slug })
    ok!('G1 operator reject => polite decline, no re-escalation, no load',
        !$FAKE.called?(:recharge) && $TG.empty? && r[:reply].to_s.match?(/can't do freeplay/i))
  ensure
    begin
      if g1_flag_saved.nil?
        ENV.delete('PATRA_APPROVAL_AUTORESUME')
      else
        ENV['PATRA_APPROVAL_AUTORESUME'] = g1_flag_saved
      end
      g1_approvals.delete_all
      if g1_was_new
        g1_rule.destroy
      else
        g1_rule.update!(g1_snap.except('id', 'created_at', 'updated_at'))
      end
      puts '[cleanup] restored G1 fixtures (flag, approvals, game_rule)'
    rescue StandardError => e
      puts "[cleanup] G1 restore failed: #{e.class}: #{e.message}"
    end
  end

  # R3-lock (G1c): freeplay-typed cashout rules still drive from the freeplay flag
  reset_run; prime_contact!(contact, [src_slug])
  GameAction.create!(account_id: account.id, agent_game_id: ag.id, contact_id: contact.id,
                     action_type: 'load', order_id: 'HARNESS_G1_FPTYPE', game_username: 'harnessuser1',
                     amount: 5, status: 'success', metadata: { freeplay: true }, executed_at: Time.current)
  g1_type = orch(account, contact, []).send(:last_deposit_for_cashout, src_slug)
  ok!('G1c freeplay-funded balance => R3 sees a freeplay-typed last deposit (assert, not rebuilt)',
      g1_type && g1_type[:type] == 'freeplay' && g1_type[:amount] == 5.0)

  puts "\n[G2 bonus generosity pattern]  (unconfigured escalates; configured % auto-applies)"
  g2_rule = GameRule.find_or_initialize_by(account_id: account.id, game_id: ag.game.id)
  g2_was_new = g2_rule.new_record?
  g2_snap = g2_was_new ? nil : g2_rule.attributes.dup
  g2_rule.assign_attributes(deposit_bonus_enabled: false)
  g2_rule.save!
  g2_keys = %w[bonus_percent first_deposit_bonus_percent bonus_min_deposit]
  g2_set = lambda do |h|
    base = (account.custom_attributes || {}).reject { |k, _| g2_keys.include?(k.to_s) }
    account.update!(custom_attributes: base.merge(h))
  end
  g2_pay = lambda do |amt, id|
    contact.update!(custom_attributes: contact.custom_attributes.merge(
      'patra_finance_logs' => [{ 'id' => id, 'status' => 'confirmed', 'amount' => amt,
                                 'recorded_at' => Time.current.iso8601, 'platform' => 'cashapp' }]
    ))
  end
  begin
    # UNCONFIGURED explicit ask -> full case + pending approval, NO load
    g2_set.call({})
    reset_run; prime_contact!(contact, [src_slug])
    g2_pay.call(30, 'HARNESS_G2_PAY0')
    r = orch(account, contact, [{ 'role' => 'user', 'content' => 'any bonus if i load 30?' }])
          .send(:handle_load_bonus, { intent: :load_bonus, game_slug: src_slug })
    ok!('G2 unconfigured bonus ask => escalates, NO load', !$FAKE.called?(:recharge) && Array(r[:labels]).include?('needs-human'))
    ok!('G2 unconfigured ask => case carries WHY GIVE/WHY NOT + deposit at hand',
        tg?('WHY GIVE') && tg?('verified $30 deposit waiting'))
    g2_appr = ApprovalRequest.where(account_id: account.id, action_type: 'load', status: 'pending')
                             .where("metadata->>'source' = 'bella_bonus'")
    ok!('G2 unconfigured ask => pending ApprovalRequest (source bella_bonus)', g2_appr.exists?)
    g2_appr.delete_all

    # CONFIGURED 20% -> 20 + 20% = 24 in ONE load, bonus flagged in metadata
    g2_set.call('bonus_percent' => 20)
    reset_run; prime_contact!(contact, [src_slug])
    GameAction.create!(account_id: account.id, agent_game_id: ag.id, contact_id: contact.id,
                       action_type: 'load', order_id: 'HARNESS_G2_PRIOR', game_username: 'harnessuser1',
                       amount: 10, status: 'success', metadata: {}, executed_at: 2.hours.ago, created_at: 2.hours.ago)
    g2_pay.call(20, 'HARNESS_G2_PAY1')
    r = orch(account, contact, [{ 'role' => 'user', 'content' => 'load 20' }])
          .send(:handle_load_intent, { intent: :load, amount: 20, game_slug: src_slug, game_username: 'harnessuser1' })
    g2_rc = $FAKE.calls.find { |c| c[0] == :recharge }
    ok!('G2 configured 20% => ONE load of exactly $24', g2_rc && g2_rc[1].to_f == 24.0)
    g2_ga = GameAction.where(contact_id: contact.id, action_type: 'load', status: 'success', amount: 24).first
    ok!('G2 configured => bonus flagged in metadata (deposit 20 + bonus 4)',
        g2_ga && g2_ga.metadata['deposit_bonus'].to_s == 'true' && g2_ga.metadata['bonus_amount'].to_f == 4.0)
    ok!('G2 reply mentions the bonus', r[:reply].to_s.include?('bonus'))

    # min-deposit gate: $20 below the $50 floor -> plain $20 load
    g2_set.call('bonus_percent' => 20, 'bonus_min_deposit' => 50)
    reset_run; prime_contact!(contact, [src_slug])
    g2_pay.call(20, 'HARNESS_G2_PAY2')
    orch(account, contact, [{ 'role' => 'user', 'content' => 'load 20' }])
      .send(:handle_load_intent, { intent: :load, amount: 20, game_slug: src_slug, game_username: 'harnessuser1' })
    g2_rc = $FAKE.calls.find { |c| c[0] == :recharge }
    ok!('G2 below bonus_min_deposit => plain $20, no bonus', g2_rc && g2_rc[1].to_f == 20.0)

    # first deposit ever -> first_deposit_bonus_percent (50%) wins over bonus_percent (20%)
    g2_set.call('bonus_percent' => 20, 'first_deposit_bonus_percent' => 50)
    reset_run; prime_contact!(contact, [src_slug])
    g2_pay.call(20, 'HARNESS_G2_PAY3')
    orch(account, contact, [{ 'role' => 'user', 'content' => 'load 20' }])
      .send(:handle_load_intent, { intent: :load, amount: 20, game_slug: src_slug, game_username: 'harnessuser1' })
    g2_rc = $FAKE.calls.find { |c| c[0] == :recharge }
    ok!('G2 first deposit ever => 50% first-deposit bonus wins ($30 load)', g2_rc && g2_rc[1].to_f == 30.0)

    # contact override 'none' blocks the configured percent
    g2_set.call('bonus_percent' => 20)
    reset_run; prime_contact!(contact, [src_slug])
    contact.update!(custom_attributes: contact.custom_attributes.merge('bonus_percent_override' => 'none'))
    g2_pay.call(20, 'HARNESS_G2_PAY4')
    orch(account, contact, [{ 'role' => 'user', 'content' => 'load 20' }])
      .send(:handle_load_intent, { intent: :load, amount: 20, game_slug: src_slug, game_username: 'harnessuser1' })
    g2_rc = $FAKE.calls.find { |c| c[0] == :recharge }
    ok!("G2 contact override 'none' => plain $20, percent blocked", g2_rc && g2_rc[1].to_f == 20.0)

    # G2e - bonus-typed last deposit falls back to default multipliers (R3 lock)
    g2_type = orch(account, contact, []).send(:last_deposit_for_cashout, src_slug)
    ok!('G2e bonus-typed deposit recognized by R3 typing (assert, not rebuilt)',
        %w[deposit bonus].include?(g2_type && g2_type[:type]))
  ensure
    begin
      g2_set.call({})
      if g2_was_new
        g2_rule.destroy
      else
        g2_rule.update!(g2_snap.except('id', 'created_at', 'updated_at'))
      end
      puts '[cleanup] restored G2 fixtures (account keys, game_rule)'
    rescue StandardError => e
      puts "[cleanup] G2 restore failed: #{e.class}: #{e.message}"
    end
  end

  puts "\n[G3 referral generosity pattern]  (master switch OFF escalates; approve pays A)"
  g3_saved_enabled = pref_row.respond_to?(:referral_enabled) ? pref_row.referral_enabled : nil
  pref_row.update!(referral_enabled: false) if pref_row.respond_to?(:referral_enabled)
  g3_keys = %w[referral_reward_mode referral_fixed_amount referral_percent referral_min_deposit]
  g3_set = lambda do |h|
    base = (account.custom_attributes || {}).reject { |k, _| g3_keys.include?(k.to_s) }
    account.update!(custom_attributes: base.merge(h))
  end
  g3_flag_saved = ENV['PATRA_APPROVAL_AUTORESUME']
  g3_referred = Contact.create!(account: account, name: 'HARNESS_REFERRED_CONTACT')
  g3_approvals = ApprovalRequest.where(account_id: account.id, action_type: 'load')
                                .where("metadata->>'source' = 'bella_referral'")
  begin
    # percent math: 10% (default) of the referred player's $50 deposit = $5
    g3_set.call({})
    GameAction.create!(account_id: account.id, agent_game_id: ag.id, contact_id: g3_referred.id,
                       action_type: 'load', order_id: 'HARNESS_G3_REFDEP', game_username: 'refuser',
                       amount: 50, status: 'success', metadata: {}, executed_at: Time.current)
    g3_pct = orch(account, contact, []).send(:referral_reward_amount, g3_referred)
    ok!('G3 percent mode (default 10%) => $5 on a $50 referred deposit', g3_pct == 5.0)

    # fixed math
    g3_set.call('referral_reward_mode' => 'fixed', 'referral_fixed_amount' => 7)
    g3_fixed = orch(account, contact, []).send(:referral_reward_amount, g3_referred)
    ok!('G3 fixed mode => $7 regardless of deposit', g3_fixed == 7.0)

    # OFF (default) referral claim -> full case + pending approval, no money
    reset_run; prime_contact!(contact, [src_slug])
    r = orch(account, contact, [{ 'role' => 'user', 'content' => 'i referred my cousin, where is my bonus?' }])
          .send(:handle_referral, { intent: :referral })
    ok!('G3 OFF => no money moved, pending reply', !$FAKE.called?(:recharge) && Array(r[:labels]).include?('needs-human'))
    ok!('G3 OFF => case carries who/what/reward', tg?('NEEDS FROM HUMAN') && tg?('reward if approved'))
    g3_appr = g3_approvals.where(status: 'pending').order(:id).last
    ok!('G3 OFF => pending ApprovalRequest (source bella_referral, $7 fixed)',
        g3_appr.present? && g3_appr.amount.to_f == 7.0)

    # operator approve -> pays A once via the normal path, referral metadata flag
    ENV['PATRA_APPROVAL_AUTORESUME'] = 'true'
    reset_run
    g3_appr.update_columns(status: 'approved')
    res = Approvals::AutoResume.execute!(g3_appr)
    g3_paid = GameAction.find_by(account_id: account.id, order_id: "appr_#{g3_appr.id}")
    ok!('G3 approve => referrer paid $7 once via the normal path',
        res[:ok] == true && $FAKE.calls.count { |c| c[0] == :recharge } == 1)
    ok!('G3 paid load carries the referral metadata flag',
        g3_paid && g3_paid.metadata['referral'].to_s == 'true' && g3_paid.amount.to_f == 7.0)
    ENV.delete('PATRA_APPROVAL_AUTORESUME')

    # G3c - referral-typed last deposit uses default multipliers in R3 typing
    g3_type = orch(account, contact, []).send(:last_deposit_for_cashout, src_slug)
    ok!('G3c referral-typed deposit recognized by R3 typing (assert, not rebuilt)',
        g3_type && g3_type[:type] == 'referral')
  ensure
    begin
      if g3_flag_saved.nil?
        ENV.delete('PATRA_APPROVAL_AUTORESUME')
      else
        ENV['PATRA_APPROVAL_AUTORESUME'] = g3_flag_saved
      end
      g3_set.call({})
      g3_approvals.delete_all
      pref_row.update!(referral_enabled: g3_saved_enabled) if pref_row.respond_to?(:referral_enabled) && !g3_saved_enabled.nil?
      Referral.where(account_id: account.id, referrer_contact_id: contact.id).destroy_all
      GameAction.where(contact_id: g3_referred.id).delete_all
      g3_referred.destroy
      puts '[cleanup] restored G3 fixtures (flag, approvals, pref, referrals, referred contact)'
    rescue StandardError => e
      puts "[cleanup] G3 restore failed: #{e.class}: #{e.message}"
    end
  end

  puts "\n[G4 escalation_context rollout]  (migrated one-liner sites now carry the full case)"
  # migrated site 1: partial-cashout failure
  reset_run(fail_withdraw: true); prime_contact!(contact, [src_slug])
  orch(account, contact, [{ 'role' => 'user', 'content' => 'cash out 20 keep the rest' }])
    .send(:handle_redeem_partial_replay, { intent: :redeem_partial_replay, game_slug: src_slug })
  ok!('G4 partial-cashout fail => full R8 context (PLAYER WANTS + NEEDS FROM HUMAN)',
      tg?('PLAYER WANTS') && tg?('NEEDS FROM HUMAN'))

  # migrated site 2: duplicate-payment hold
  # MEGA-AUDIT timing fix: the prior load must predate the payment's
  # recorded_at, or payment_already_loaded?'s amount fallback
  # (orchestrator:2316-2321, created_at >= recorded) filters the payment out
  # and the dup guard (:423) never fires. 2 minutes keeps it inside the
  # guard's 10-minute window.
  reset_run; prime_contact!(contact, [src_slug])
  GameAction.create!(account_id: account.id, agent_game_id: ag.id, contact_id: contact.id,
                     action_type: 'load', order_id: 'HARNESS_G4_DUP', game_username: 'harnessuser1',
                     amount: 25, status: 'success', metadata: {}, executed_at: 2.minutes.ago,
                     created_at: 2.minutes.ago, updated_at: 2.minutes.ago)
  contact.update!(custom_attributes: contact.custom_attributes.merge(
    'patra_finance_logs' => [{ 'id' => 'HARNESS_G4_PAY', 'status' => 'confirmed', 'amount' => 25,
                               'recorded_at' => Time.current.iso8601, 'platform' => 'cashapp' }]
  ))
  r = orch(account, contact, [{ 'role' => 'user', 'content' => 'load 25' }])
        .send(:handle_load_intent, { intent: :load, amount: 25, game_slug: src_slug, game_username: 'harnessuser1' })
  ok!('G4 duplicate-payment hold => held with full context (DUPLICATE PAYMENT + NEEDS FROM HUMAN)',
      !$FAKE.called?(:recharge) && tg?('DUPLICATE PAYMENT') && tg?('NEEDS FROM HUMAN'))

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
  # MEGA-AUDIT: destroy ALL harness conversations BEFORE the contact (FK order;
  # also removes the contact_inbox rows via the contact destroy that follows).
  begin
    convos = Conversation.where(contact_id: contact.id)
    convo_count = convos.count
    convos.destroy_all
    puts "[cleanup] destroyed #{convo_count} harness conversation(s) for throwaway contact #{contact.id}"
  rescue StandardError => e
    puts "[cleanup] conversation cleanup failed: #{e.class}: #{e.message}"
  end
  # MEGA-AUDIT: catch-all for pending ApprovalRequests tied to the throwaway
  # contact (R7 bella_over_threshold targets Contact; generosity approvals
  # carry metadata contact_id). The inline deletes in R7/G2 cover the happy
  # path; this covers a crash between create and delete.
  begin
    leaked = ApprovalRequest.where(account_id: account.id, status: 'pending')
                            .where("metadata->>'contact_id' = ? OR (target_type = 'Contact' AND target_id = ?)",
                                   contact.id.to_s, contact.id)
    leaked_n = leaked.count
    leaked.delete_all if leaked_n.positive?
    puts "[cleanup] removed #{leaked_n} leaked pending ApprovalRequest(s)" if leaked_n.positive?
  rescue StandardError => e
    puts "[cleanup] leaked-approval cleanup failed: #{e.class}: #{e.message}"
  end
  # MEGA-AUDIT: unlink any REAL referral that link_referred_on_account_creation
  # attached to the throwaway contact during R6/TABA-2 creates (orchestrator
  # :4473-4489 links the newest pending referral to WHOEVER creates an account
  # next - PROD finding). Reset, don't destroy: the row belongs to real activity.
  # Must run BEFORE contact.destroy (referrals.referred_contact_id FK).
  begin
    hijacked = Referral.where(account_id: account.id, referred_contact_id: contact.id)
    hijacked_n = hijacked.count
    hijacked.find_each { |r| r.update_columns(referred_contact_id: nil, status: 'pending') }
    puts "[cleanup] unlinked #{hijacked_n} real referral(s) from throwaway contact" if hijacked_n.positive?
  rescue StandardError => e
    puts "[cleanup] referral unlink failed: #{e.class}: #{e.message}"
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
  begin
    if defined?(cg_saved) && cg_saved.is_a?(Hash) && cg_saved.any? && defined?(pref_row) && pref_row
      pref_row.update!(cg_saved)
      puts '[cleanup] restored confirm_before_load/confirm_before_cashout prefs'
    end
  rescue StandardError => e
    puts "[cleanup] confirm-gate pref restore failed: #{e.class}: #{e.message}"
  end
  begin
    if defined?(ref_en_saved) && !ref_en_saved.nil? && defined?(pref_row) && pref_row.respond_to?(:referral_enabled)
      pref_row.update!(referral_enabled: ref_en_saved)
      puts '[cleanup] restored referral_enabled pref'
    end
  rescue StandardError => e
    puts "[cleanup] referral_enabled restore failed: #{e.class}: #{e.message}"
  end
  begin
    if defined?(Payments::EmailConfirmationService) && Payments::EmailConfirmationService.method_defined?(:orig_check_all_harness)
      Payments::EmailConfirmationService.class_eval do
        alias_method :check_all, :orig_check_all_harness
        remove_method :orig_check_all_harness
      end
      puts '[cleanup] restored EmailConfirmationService#check_all'
    end
  rescue StandardError => e
    puts "[cleanup] check_all restore failed: #{e.class}: #{e.message}"
  end
  restore_stubs
  puts '[cleanup] restored stubs'
end
