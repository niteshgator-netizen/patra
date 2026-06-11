# PATRA MONEY-FLOWS RUN 3 - LOG

## ROLLBACK
Rollback hash (state before this run): `ef718c8d29f4c2fe7466bc92c4b509eb127b5515`
Full rollback: `git reset --hard ef718c8d29f4c2fe7466bc92c4b509eb127b5515`

## MORNING SUMMARY (run complete, NOT pushed)
Freeplay, bonus, and referral now share one operator-confirmed pattern: per-contact override
first, operator-configured auto flow preserved (GameRule / referral_enabled), and the launch
default escalates to Telegram with the full case (WHY GIVE / WHY NOT derived from real
GameAction data) plus a pending ApprovalRequest. Approvals::AutoResume gained a 'load' branch
(same dark PATRA_APPROVAL_AUTORESUME flag, exactly-once appr_<id> order_id) so operator approval
pays through the normal executor path with the right freeplay/deposit_bonus/referral metadata
flag - R3 deposit typing and TABA-1 single-record both hold (harness-asserted, not rebuilt).
G2's configured percent auto-attaches at the handle_load_intent sites as ONE load of
amount+bonus on the unchanged F12 deterministic order_id. G4 migrated 28 one-liner Telegram
reasons to full escalation_context cases (the 2 success-notification reports and the transfer
failed-list hash keys were intentionally left). Orchestrator byte-patched only (4,597 lines,
CRLF preserved, ruby -c after every patch; the G4 batch ran through tmp/g4_apply.rb - same
CRLF-preserving assert-unique contract as bpatch.rb, one driver for 28 single-line sites).
Harness grew 1,101 -> 1,393 lines, all additive; every G scenario pins and restores its
GameRule/pref/account-key/ENV fixtures. No forbidden/owner-WIP file touched. No migration
required (optional columns documented in docs/proposed_migrations/).

Verified by me now: syntax of every touched file after every patch, unique-anchor matching,
no dangling references from the replaced freeplay handler, CRLF intact.
NOT verified locally (Rails cannot boot): harness execution - Render is the gate.

RENDER GATE (operator runs):
  bundle exec rails runner script/patra_money_harness.rb   # RESULT: PASS incl. all R+S+G cases
  reply smoke 100/100 unchanged; intents 128/128 unchanged

## RULE CHECKLIST + COMMITS
- [x] Log init / Phase 0 ............ a09208ca2
- [x] G1 freeplay ................... 15b0a2c97  (proof: override approve loads $5 w/ flag; daily limit; override deny; default escalates w/ WHY GIVE/WHY NOT + pending approval; approve loads once via AutoResume w/ freeplay flag; reject -> polite decline; G1c freeplay-typed R3 lock - 10 cases)
- [x] G2 bonus ...................... bb1a13502  (proof: unconfigured ask escalates w/ case + approval, no load; 20% => exactly $24 single load w/ metadata; min-deposit gate; first-deposit 50% wins => $30; contact 'none' blocks; G2e typing lock - 8 cases)
- [x] G3 referral ................... 6a3492ac1  (proof: percent 10% of $50 => $5; fixed => $7; OFF escalates w/ who/what/reward + pending approval; approve pays referrer $7 once w/ referral flag; G3c typing lock - 7 cases)
- [x] G4 escalation rollout ......... 5dfcba3ec  (28 sites migrated; proof: partial-cashout fail + duplicate-payment hold both emit PLAYER WANTS/NEEDS FROM HUMAN - 2 cases)
- [x] Final log + dump .............. (this commit; optional columns in docs/proposed_migrations/20260610_moneyflows3_generosity_settings.rb)

## PHASE 0 FINDINGS (verified by reading the files this session)

### Freeplay today (orchestrator handle_load_freeplay:576)
GameRule-driven only: freeplay_enabled false (or no row) -> ONE-LINER telegram + "isn't available".
Enabled -> tier eligibility, per-game daily/weekly limits (freeplay_max_per_day default 1,
freeplay_max_per_week 3), optional deposit-first, then execute_game_api('recharge') with
metadata `{ freeplay: true, source: 'bella_freeplay' }` - the TABA-1 single-record convention
(executor audits ONE GameAction; the freeplay flag keeps it out of deposit math). No per-contact
override, no approval flow, no decision logging.

### Bonus today (handle_load_bonus:714 + handle_load_intent informational block)
GameRule deposit_bonus_* driven. deposit_bonus_enabled false -> SILENT fallback to plain
handle_load_intent (no escalation, no ask honored). Enabled -> first-deposit-only check, tier,
min amount, calculate_bonus (pct, max), ONE load of deposit+bonus via execute_game_api with
metadata `{ deposit_bonus: true, deposit_amount:, bonus_amount:, payment_id: }` + F12
bonus_order_id (R7 hold already wired in Run 1). handle_load_intent ALSO has a post-load
"auto-bonus" block that is informational only ("Next iteration: load base+bonus together" - that
next iteration is G2d). Bonus metadata convention to follow: deposit_bonus/deposit_amount/
bonus_amount flags on a single GameAction.

### Referral today (handle_referral:3716 + Games::ReferralBonusService)
handle_referral: creates a pending Referral row + ONE-LINER telegram + canned reply. BUG-4 fix
lives in ReferralBonusService.check_and_pay: fires only from link_referred (account-creation
linking), gated on pref.referral_enabled (DEFAULT FALSE - master switch), referral_bonus_type
'freeplay' only, optional require_deposit, pays referrer+referred as freeplay-flagged loads
via ActionExecutor. ReplyPreference referral columns exist (referral_enabled, bonus_referrer 5,
bonus_new_player 5, bonus_type, require_deposit, tracking_method, messages). KEEP this as the
configured/ON path - G3 adds the OFF (default) escalate+approve path in the orchestrator only.

### F15 approve path (Approvals::AutoResume + ApprovalRequest)
ApprovalRequest.approve! -> after_update_commit enqueues AutoResumeJob ONLY when
ENV PATRA_APPROVAL_AUTORESUME=true (shipped dark, default off). AutoResume.execute! currently
SKIPS anything that is not action_type 'cashout' (skipped: :not_cashout). Exactly-once via
order_id "appr_<id>" on the game_actions unique index. To make "operator approve -> money moves
through the normal load path" real for G1-G3, AutoResume gains an action_type 'load' branch
(non-hot file, normal edit). Flag stays dark: with it off, approval remains the manual record,
identical to R7's D8 behavior.

### Settings / per-contact reads
Run-1 pattern reused: reply_preferences column if it exists -> account.custom_attributes['<key>']
-> stated default (generosity_setting helper). Per-contact overrides live in
contact.custom_attributes ('freeplay_auto', 'bonus_percent_override'). R3's freeplay-typed
cashout (cashout_freeplay_multiplier/max) and bonus/referral default-multiplier fallback already
exist and are harness-locked - G1c/G2e/G3c only add assertions.

### G4 inventory
44 human_escalation sites in the orchestrator; Runs 1-2 already converted the R1/R4/R6/R7/S1/S2/S3
ones to escalation_context. Remaining one-liners to migrate: forbidden-auto-intent, duplicate
payment guard, load-fail + create-fail sites (load_intent, username_provided, account_creation x3,
transfer-create x2), velocity x2, transfer balance-read fail, transfer cashout-fail, transfer
unclear, complaint_angry, tech_issue, partial-cashout fail, silent-fail/timeout responses, and
the no-URL info handlers. Freeplay/bonus/referral sites are rewritten by G1-G3 themselves.

## DECISIONS
- D1 (configured flows preserved): GameRule freeplay_enabled / deposit_bonus_enabled and
  referral_enabled remain the "configured" switches; when on, the pre-G behavior (with its limits
  and messages) still runs. The G pattern replaces only the UNCONFIGURED branches: freeplay
  one-liner decline, bonus silent plain-load fallback, referral one-liner telegram.
- D2 (AutoResume 'load' branch): approve->execute reuses the F15 dark-flag machinery. R7's
  bella_over_threshold approvals carry target_type 'Contact' and stay manual-on-approve (the new
  branch requires target_type AgentGame + username; invalid ones notify "handle manually").
  Generosity approvals store target AgentGame + game_username + contact_id + flag metadata so the
  executed GameAction carries the right freeplay/deposit_bonus/referral flag for R3 typing.
- D3 (daily limit applies everywhere): freeplay_daily_limit_per_player gates override-approve,
  GameRule-auto, and the escalate path alike (a player over the limit gets the polite decline
  without pinging the operator). Precedence: setting -> GameRule.freeplay_max_per_day -> 1.
  freeplay_amount precedence: player-tier override (existing) -> setting -> GameRule.freeplay_amount -> 5.
- D4 (reject -> polite decline): a rejected generosity ApprovalRequest (same source+contact,
  last 24h) makes the next ask decline politely instead of re-escalating; a still-pending request
  dedupes (no approval spam).
- D5 (G2 auto-% lives in handle_load_intent): the configured % attaches at the two
  handle_load_intent load sites (ONE load of amount+bonus, deposit_bonus metadata, SAME
  deterministic order_id so F12 holds). GameRule-bonus and new-% never stack: handle_load_bonus
  prefers the GameRule flow; the informational post-load block is untouched. username_provided /
  account-creation loads stay plain (payment-exact) - logged as out of G2d scope.
- D6 (signup_bonus_amount): setting reader exists (generosity_setting) but it is NOT wired to
  account creation in this run - no proving case asked for it and wiring it would move money in
  an untested path. Documented for a future run.
- D7 (decision log): every generosity decision appends to
  contact.custom_attributes['patra_generosity_log'] (kind/decision/amount/source/at, capped at
  50) in addition to the GameAction metadata when money moved.
- D8 (G3 reward TBD): percent_of_deposit with no linked/deposited referred player creates the
  approval with amount 0 + 'reward_pending_referred_deposit' - the case text says so; AutoResume
  treats amount<=0 as not executable (manual). Fixed mode always has a real amount.

## ASSUMPTIONS
- A1: Local Rails cannot boot; ruby -c + additive harness cases are the proof; Render is the gate.
- A2: Account 2 may or may not have GameRule rows / referral prefs set - every G harness scenario
  pins the rows/flags it needs (snapshot + restore in ensure), same pattern as R3/R4/S2.
- A3: ApprovalRequest.requesting_user falls back to the account's first user; if an account has
  no user the approval row is skipped (rescued) and the Telegram escalation still carries the case.

## SETTINGS KEYS THIS RUN (launch default = everything escalates until configured)
| Key | Where | Default | Used by |
|-----|-------|---------|---------|
| freeplay_amount | pref col (none today) -> account custom_attrs -> 5 | 5 | G1 |
| freeplay_daily_limit_per_player | setting -> GameRule.freeplay_max_per_day -> 1 | 1 | G1 |
| bonus_percent | setting -> nil (unconfigured) | nil | G2 |
| first_deposit_bonus_percent | setting -> nil | nil | G2 (wins on first deposit) |
| bonus_min_deposit | setting -> nil | nil | G2 |
| signup_bonus_amount | setting -> nil (reader only, NOT wired - D6) | nil | - |
| referral_reward_mode | setting -> 'percent_of_deposit' | percent_of_deposit | G3 |
| referral_percent | setting -> 10 | 10 | G3 |
| referral_fixed_amount | setting -> nil | nil | G3 fixed mode |
| referral_min_deposit | setting -> nil | nil | G3 (case text gate) |
| contact 'freeplay_auto' | contact custom_attrs | absent | G1 override (approve/deny) |
| contact 'bonus_percent_override' | contact custom_attrs | absent | G2 override (number/'none') |
| referral_enabled | existing pref column | false | G3 master switch (BUG-4) |

## PER-RULE COMMITS
(filled as commits land)
