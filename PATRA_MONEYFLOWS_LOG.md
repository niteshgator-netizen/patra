# PATRA MONEY-FLOWS RUN 1 - LOG

## ROLLBACK
Rollback hash (state before this run): `9672149893dd9ab35b2a0b54f53f20e31cb18a0b`
Full rollback: `git reset --hard 9672149893dd9ab35b2a0b54f53f20e31cb18a0b`
Per-rule rollback hashes listed in the checklist below as commits land.

## MORNING SUMMARY
(to be filled at end of run)

## RULE CHECKLIST
- [ ] R8 escalation-context helper (done first; used by R1/R6/R7)
- [ ] R1 transfer modes off/deposit_only/whole, half-fail offer, no-username reply
- [ ] R2 replay-from-balance loads exactly N (ALREADY SATISFIED - locking assertion)
- [ ] R3 cashout min/max from LAST deposit, type-aware, state real minimum
- [ ] R4 over-max mode cash_whole | pay_max_recharge
- [ ] R5 partial keep-in recorded as new deposit, Telegram labels RELOAD
- [ ] R6 account creation ask use-old/make-new + failure ladder (R6a ALREADY SATISFIED - locking assertion)
- [ ] R7 auto_load_threshold dollar gate + F12 coverage assert
- [ ] Final: proposed migration doc + dump

## PHASE 0 FINDINGS (verified by reading full files this session)

Files read in full: app/services/games/conversation_orchestrator.rb (3,333 lines, CRLF),
script/patra_money_harness.rb (535 lines), app/models/game_rule.rb, app/models/reply_preference.rb,
app/services/games/action_executor.rb, app/services/approvals/cashout_approval_gate.rb,
app/services/approvals/auto_resume.rb, app/models/approval_request.rb, relevant migrations.

### Return shapes (all orchestrator handlers return `{ reply: String, labels: Array }` or nil)
- ActionExecutor#load_player / #cashout_player / #add_player / #reset_player_password return
  `{ ok: true/false, action: GameAction, response: Hash }` on success,
  `{ ok: false, action:, error:, code: }` on failure. cashout_player can return
  `{ ok: false, code: 'approval_required', approval_request_id: }` (gate > $500 default).
- handle_transfer_between_games: parses plan via DeepSeek then regex; velocity guard; reads source
  balance; below-cashout-min fork uses transfer_mode ('whole' fallback) + transfer_deposit_shortfall_mode;
  cashes out via cashout_player (no order_id), loads targets via load_player (no order_id);
  always Telegrams a real-state report containing "Remaining:".
- handle_replay_from_balance: READ-ONLY (balance check, no money). Harness-locked already.
- handle_cashout_intent: NEVER calls the panel. Validates tier-block, velocity, GameRule
  (cashout_enabled, absolute cashout_min_amount, max from SUM of deposits), screenshot pref,
  confirm pref; then Telegram escalation to cashier. min_cashout is COMPUTED but NEVER compared
  to the requested amount (only absolute min + max are enforced).
- handle_redeem_partial_replay: verb-adjacent amount (TABA-3), dedup guard, cashout_player of the
  partial amount, Telegram "rest left to play". Kept amount NOT recorded anywhere.
- handle_new_account_reissue: clears vault creds, immediately add_player (auto username), failure ->
  Telegram dead-end. No resend/reset ladder.
- handle_account_creation_request: existing account -> auto-RESENDS creds (does not ask old-vs-new);
  no payment -> creates account first then asks payment handle (NO deposit gate - R6a satisfied);
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
| R1 | NEEDS CHANGES | transfer_mode only applies in below-cashout-min fork; values whole/deposit_only only, fallback 'whole'; no 'off'; half-fail reply lacks "another game or take the money" offer; no-username reply asks for username |
| R2 | ALREADY SATISFIED | load amount = requested/payment amount, balance never read on load path |
| R3 | NEEDS CHANGES | min/max from SUM of deposits, not LAST; multiplier-min never enforced; type from totals not last-deposit type |
| R4 | NEEDS CHANGES | over-max = flat decline reply; no cashout_overmax_mode |
| R5 | PARTIAL | verb-adjacent amount green (TABA-3); kept amount not recorded, no RELOAD telegram label |
| R6a | ALREADY SATISFIED | no-payment create path creates account, then offers payment handle |
| R6b | NEEDS CHANGES | existing account -> auto-resend, never asks use-old vs make-new |
| R6c | NEEDS CHANGES | reissue jumps straight to create-new; create/reset failures dead-end at Telegram |
| R7 | NEEDS CHANGES | no dollar auto-load threshold on orchestrator path (only per-agent max_load_amount credential, default unlimited). F12: all 6 payment-funded load sites verified guarded - no gap |
| R8 | NEEDS CHANGES | no escalation-context helper; reasons are one-liners |

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
  transfer fork.
- D4 (R4 executes no panel calls): handle_cashout_intent has never moved money (payout is
  cashier-manual via Telegram per the Phase 6.5 design note in the file). R4 is implemented as
  amount math + player messaging + full-context Telegram escalation; the actual whole-balance redeem /
  max-payout + leftover recharge stays with the cashier. No new panel calls added to this handler.
- D5 (R6c ladder reading): R6b's use-old branch = resend/reset (rungs 1-2); explicit
  new-account/reissue request enters at rung 3 (create new). The FAILURE ladder means: on each rung's
  FAILURE fall to the next rung instead of dead-ending - reset fail -> create new; create fail ->
  suggest a different game + Telegram human. This keeps both existing reissue harness assertions green.
- D6 (harness fixture pins, assertions untouched): two existing scenarios were written under
  pre-R1/R7 semantics and get SETUP pins only (no assertion changed): (a) the transfer block pins
  transfer_mode='whole' (its scenarios have zero deposit history, which under R1 deposit_only would
  legitimately move nothing); (b) the harness globally pins account custom_attributes
  auto_load_threshold=1,000,000 (F13 asserts a $999 load with the per-agent cap unset goes through;
  R7's $200 default would otherwise block it - F13 tests the per-agent cap, not the new gate).
  Both pins are snapshotted and restored in ensure. New R1/R7 scenarios set their own values.
- D7 (R5 keep-in record): the kept amount is recorded as a GameAction(action_type='load',
  status='success') with metadata `keep_in_from_cashout: true` and NO panel call (the money never
  left the game). This makes it the "most recent deposit" for R3 min/max and R1 deposit_only math,
  exactly per the rule. Telegram reason carries "RELOAD (keep-in-from-cashout)".
- D8 (R7 approval reuse): F15 AutoResume only auto-executes action_type='cashout'. Over-threshold
  loads create an ApprovalRequest(action_type='load', status='pending') so the operator approves and
  loads manually - i.e. "load only on operator approval" without inventing a new auto-execute path.

## ASSUMPTIONS
- A1: account 2's ReplyPreference row carries transfer_mode='whole' (DB column default; never
  explicitly changed). New R1 harness cases pin the pref per scenario so the gate is deterministic
  either way.
- A2: GameRule rows may or may not exist for account 2's games. R3/R4 harness cases
  find_or_initialize the GameRule for the test game, set the fields they assert against, snapshot
  and restore (destroy if created).
- A3: Local Rails cannot boot here; proof is `ruby -c` + additive harness cases. The Render gate
  (`bundle exec rails runner script/patra_money_harness.rb`) is the operator-run final proof.
- A4: "referral" deposit type (R3) has no type-specific GameRule rows today; referral- and
  bonus-typed last deposits use the default multipliers (only freeplay has type-specific fields:
  cashout_freeplay_multiplier / cashout_freeplay_max).

## PER-RULE COMMITS
(filled in as commits land)
