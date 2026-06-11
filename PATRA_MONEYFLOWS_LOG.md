# PATRA MONEY-FLOWS RUN 1 - LOG

## ROLLBACK
Rollback hash (state before this run): `9672149893dd9ab35b2a0b54f53f20e31cb18a0b`
Full rollback: `git reset --hard 9672149893dd9ab35b2a0b54f53f20e31cb18a0b`
Per-rule rollback: `git revert <commit>` (commits listed below) or reset to the commit BEFORE it.

## MORNING SUMMARY (run complete, NOT pushed)
All 8 operator-confirmed money rules are implemented and committed, one commit per rule,
on branch main (local only - NO push happened). The orchestrator was changed exclusively via
the CRLF-preserving byte-patcher (tmp/bpatch.rb, assert-unique-anchor); `ruby -c` passed after
every patch and at the end (orchestrator, harness, reply_preference model all Syntax OK,
CRLF preserved). The harness grew 535 -> 905 lines, ALL additions additive; two legacy
scenarios got setup-only pins (no assertion text changed - see D6). Local Rails cannot boot
here, so the Render gate below is the final proof.

Verified by me now: syntax of every touched file, anchor-unique patches, no dangling
references to removed variables, F12 coverage of all 6 payment-funded load sites (code read)
plus a new behavioral race-loser case at the username_provided site.
NOT yet verified (needs Render): the harness run itself + reply smoke 100/100.

RENDER GATE (operator runs):
  bundle exec rails runner script/patra_money_harness.rb   # must end RESULT: PASS (incl. all new R1-R8 cases)
  reply smoke must stay 100/100 unchanged

## RULE CHECKLIST + COMMITS
- [x] Log init / Phase 0 ............ a48bd3640
- [x] R8 escalation_context helper .. efe1827e0  (proof: "R8 helper includes ..." x6 harness cases)
- [x] R1 transfer modes ............. ee03c3433  (proof: "R1 OFF/DEPOSIT_ONLY/WHOLE/NO SOURCE USERNAME/HALF-FAIL" x10 cases)
- [x] R2 replay-from-balance LOCK ... 04dde233d  (already satisfied; proof: "R2 ... recharge is EXACTLY $10")
- [x] R3 min/max from LAST deposit .. cfecb83fb  (proof: "R3 below min ... $20", "R3 LAST deposit governs", "R3 freeplay-typed")
- [x] R4 over-max modes ............. 2ccd2bef5  (proof: "R4 DEFAULT cash_whole", "R4 pay_max_recharge" x5 cases)
- [x] R5 keep-in = new deposit ...... 7743a15f5  (proof: "R5 kept $20 recorded", "R5 telegram RELOAD", "R5 now the LAST deposit")
- [x] R6 choice + failure ladder .... 1f5bb5024  (proof: "R6a/R6b/R6c" x9 cases; existing reissue assertions untouched and still asserted)
- [x] R7 dollar threshold + F12 ..... cf7c535b2  (proof: "R7 over/at/custom threshold" + "R7/F12 username_provided race loser")
- [x] Final log + dump .............. (this commit)

## SETTINGS KEYS (all read pref-column -> account.custom_attributes -> default; NO migration needed)
| Key | Values | Default | Where it lives today |
|-----|--------|---------|----------------------|
| transfer_mode | off / deposit_only / whole | deposit_only (code fallback) | reply_preferences column EXISTS (DB default 'whole' - see D2); model now allows 'off' |
| cashout_overmax_mode | cash_whole / pay_max_recharge | cash_whole | custom_attributes (column proposed) |
| auto_load_threshold | dollars > 0 | 200 | custom_attributes (column proposed; name collision noted in D1) |

Proposed migration (NOT wired): docs/proposed_migrations/20260610_moneyflows_reply_preferences.rb

## PHASE 0 FINDINGS (verified by reading full files this session)

Files read in full: app/services/games/conversation_orchestrator.rb (3,333 lines pre-run, CRLF),
script/patra_money_harness.rb (535 lines pre-run), app/models/game_rule.rb, app/models/reply_preference.rb,
app/services/games/action_executor.rb, app/services/approvals/cashout_approval_gate.rb,
app/services/approvals/auto_resume.rb, app/models/approval_request.rb, relevant migrations.

### Return shapes (all orchestrator handlers return `{ reply: String, labels: Array }` or nil)
- ActionExecutor#load_player / #cashout_player / #add_player / #reset_player_password return
  `{ ok: true/false, action: GameAction, response: Hash }` on success,
  `{ ok: false, action:, error:, code: }` on failure. cashout_player can return
  `{ ok: false, code: 'approval_required', approval_request_id: }` (gate > $500 default).
- handle_transfer_between_games: parses plan via DeepSeek then regex; velocity guard; reads source
  balance; (pre-run) below-cashout-min fork used transfer_mode ('whole' fallback) + shortfall mode;
  cashes out via cashout_player (no order_id), loads targets via load_player (no order_id);
  always Telegrams a real-state report containing "Remaining:".
- handle_replay_from_balance: READ-ONLY (balance check, no money). Harness-locked already.
- handle_cashout_intent: NEVER calls the panel. (Pre-run) validated tier-block, velocity, GameRule
  (cashout_enabled, absolute cashout_min_amount, max from SUM of deposits), screenshot pref,
  confirm pref; then Telegram escalation to cashier. min_cashout was COMPUTED but NEVER compared
  to the requested amount.
- handle_redeem_partial_replay: verb-adjacent amount (TABA-3), dedup guard, cashout_player of the
  partial amount, Telegram "rest left to play". (Pre-run) kept amount NOT recorded anywhere.
- handle_new_account_reissue: (pre-run) cleared vault creds, immediately add_player, failure ->
  Telegram dead-end. No resend/reset ladder.
- handle_account_creation_request: (pre-run) existing account -> auto-RESENT creds; no payment ->
  creates account first then asks payment handle (NO deposit gate - R6a satisfied);
  with payment -> create + F12-guarded load.
- handle_load_intent: freeplay/bonus subroute, confirm-before-load pref, payment gate
  (find_matching/find_unloaded confirmed payment from contact patra_finance_logs), username gate,
  duplicate-payment guard, F12 deterministic order_id, code-8 auto-create+retry, bonus info,
  tier auto-promote. Loads EXACTLY the requested/payment amount - never reads in-game balance (R2 satisfied).
- Load sites executing money: handle_load_intent (2 calls), handle_username_provided (2),
  handle_account_creation_request (1 - the F12 "5th site", guarded), handle_load_bonus (1 via
  execute_game_api with bonus_order_id), handle_load_freeplay (execute_game_api, NO order_id -
  not payment-funded, out of F12 scope by design), transfer target loads + transfer-create load
  (no order_id - funded by a just-executed cashout, not a payment; dedup guard covers transfer).

### Rule status BEFORE editing
| Rule | Status | Evidence |
|------|--------|----------|
| R1 | NEEDED CHANGES | transfer_mode only applied in below-cashout-min fork; no 'off'; half-fail reply lacked the offer; no-username reply asked for username |
| R2 | ALREADY SATISFIED | load amount = requested/payment amount, balance never read on load path |
| R3 | NEEDED CHANGES | min/max from SUM of deposits, not LAST; multiplier-min never enforced |
| R4 | NEEDED CHANGES | over-max = flat decline reply; no cashout_overmax_mode |
| R5 | PARTIAL | verb-adjacent amount green (TABA-3); kept amount not recorded, no RELOAD label |
| R6a | ALREADY SATISFIED | no-payment create path creates account, then offers payment handle |
| R6b | NEEDED CHANGES | existing account -> auto-resend, never asked use-old vs make-new |
| R6c | NEEDED CHANGES | reissue jumped straight to create-new; failures dead-ended at Telegram |
| R7 | NEEDED CHANGES | no dollar auto-load threshold on orchestrator path. F12: all 6 payment-funded load sites verified guarded - no gap |
| R8 | NEEDED CHANGES | no escalation-context helper; reasons were one-liners |

## DECISIONS
- D1 (R7 name collision): `auto_load_threshold` already exists as an EMAIL-CONFIDENCE score
  (default 80) inside `account.custom_attributes['payment_scoring_config']` (per-platform), used by
  reply_service/email_confirmation_service. R7's new key is a DOLLAR threshold and lives at
  reply_preferences.auto_load_threshold (column proposed) with fallback to TOP-LEVEL
  `account.custom_attributes['auto_load_threshold']`, default 200. Different namespace, no code path
  overlap; operator should be aware the two share a name.
- D2 (R1 default vs DB default): reply_preferences.transfer_mode column has DB default 'whole', so
  existing rows (incl. account 2) read 'whole' and keep whole-balance transfers. The operator default
  'deposit_only' is implemented as the CODE fallback (blank pref -> custom_attributes -> 'deposit_only')
  plus a proposed migration changing the column default. Existing explicit values win - flipping
  account 2 to deposit_only is a one-line settings change for the operator, not done by this run.
- D3 (R1 supersedes shortfall mode): R1 defines deposit_only moveable = min(most recent deposit,
  current balance). That makes transfer_deposit_shortfall_mode='refuse' unreachable on the new path
  (cap-by-balance is built in, matching 'transfer_available'). Method kept, no longer consulted by the
  transfer fork. game_rules_for is also no longer consulted by the transfer fork (kept, harmless).
- D4 (R4 executes no panel calls): handle_cashout_intent has never moved money (payout is
  cashier-manual via Telegram per the Phase 6.5 design note in the file). R4 is implemented as
  amount math + player messaging + full-context Telegram escalation; the actual whole-balance redeem /
  max-payout + leftover recharge stays with the cashier. No new panel calls added to this handler.
- D5 (R6c ladder reading): R6b's use-old branch = resend/reset (rungs 1-2); explicit
  new-account/reissue request enters at rung 3 (create new). The FAILURE ladder means: on each rung's
  FAILURE fall to the next rung instead of dead-ending - reset fail -> create new; create fail ->
  suggest a different game + Telegram human (R8 context). This keeps both existing reissue harness
  assertions green. silent_fail/timeout add-failures keep their dedicated handling (they already
  escalate and must not store creds).
- D6 (harness fixture pins, assertions untouched): two existing scenarios were written under
  pre-R1/R7 semantics and got SETUP pins only (no assertion changed): (a) the legacy transfer block
  pins transfer_mode='whole' (its scenarios have zero deposit history, which under R1 deposit_only
  would legitimately move nothing); (b) the harness globally pins account custom_attributes
  auto_load_threshold=1,000,000 (F13 asserts a $999 load with the per-agent cap unset goes through;
  R7's $200 default would otherwise block it - F13 tests the per-agent cap, not the new gate).
  Both pins are snapshotted and restored in ensure. New R1/R7 scenarios set their own values.
- D7 (R5 keep-in record): the kept amount is recorded as a GameAction(action_type='load',
  status='success') with metadata `keep_in_from_cashout: true` and NO panel call (the money never
  left the game). This makes it the "most recent deposit" for R3 min/max and R1 deposit_only math,
  exactly per the rule. Telegram reason carries "RELOAD (keep-in-from-cashout) ... NOT a fresh deposit".
- D8 (R7 approval reuse): F15 AutoResume only auto-executes action_type='cashout'. Over-threshold
  loads create an ApprovalRequest(action_type='load', status='pending') so the operator approves and
  loads manually - i.e. "load only on operator approval" without inventing a new auto-execute path.
  Duplicate messages don't stack approvals (pending request per payment_id is checked first).
- D9 (R7 + account creation): account creation has NO deposit gate (R6a), so on the
  create-with-payment path the account IS still created and creds sent; only the LOAD is held when
  the deposit is over threshold.
- D10 (R1 transfers and R3 minimums): "normal cashout rules apply" on transfers is read as the
  operational guards (velocity, dedup, approval gate, credential caps - all already on both legs).
  The R3 multiplier minimum is NOT applied to the transfer's cashout leg - deposit_only explicitly
  allows moving the deposit even when winnings are below the cashout minimum.

## ASSUMPTIONS
- A1: account 2's ReplyPreference row carries transfer_mode='whole' (DB column default; never
  explicitly changed). New R1 harness cases pin the pref per scenario so the gate is deterministic
  either way; legacy transfer scenarios are pinned to 'whole'.
- A2: GameRule rows may or may not exist for account 2's games. R3/R4 harness cases
  find_or_initialize the GameRule for the test game, set the fields they assert against, snapshot
  and restore (destroy if created).
- A3: Local Rails cannot boot here; proof is `ruby -c` + additive harness cases. The Render gate
  (`bundle exec rails runner script/patra_money_harness.rb`) is the operator-run final proof.
- A4: "referral" deposit type (R3) has no type-specific GameRule rows today; referral- and
  bonus-typed last deposits use the default multipliers (only freeplay has type-specific fields).
- A5: R7 over-threshold ApprovalRequest uses target_type 'Contact' (the load has no single
  AgentGame until executed); requesting_user falls back to the account's first user - if the
  account has no user the record is skipped (rescued) and the Telegram escalation still fires.

## FILES TOUCHED (whole run)
- app/services/games/conversation_orchestrator.rb  (HOT - byte-patched only; 3,333 -> 3,702 lines)
- script/patra_money_harness.rb                    (additive; 535 -> 905 lines)
- app/models/reply_preference.rb                   (1 line: allow 'off' in transfer_mode validation)
- docs/proposed_migrations/20260610_moneyflows_reply_preferences.rb (new, not wired)
- PATRA_MONEYFLOWS_LOG.md (this file), tmp/bpatch.rb + tmp/r*_old/new fragments (tooling, uncommitted)
