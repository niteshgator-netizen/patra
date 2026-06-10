# PATRA OVERNIGHT GUARDIAN — TAB A RUN LOG (state file)

OWNER: TAB A (overnight guardian). Siblings: TAB B (backend hardening, PATRA_LAUNCH_LOG.md), TAB C (admin console, PATRA_FEAT_LOG.md) — NEVER touch their logs or lanes.
ROLLBACK_HASH=5bfb2862a396b21f95361d1dd9dcc01637ec04a4
STARTED: 2026-06-10
MODEL: Fable 5 (stay on it the whole run)

NOTES (Phase 0 facts):
- PATRA_MASTER_COMPLETE.md does NOT exist (checked 2026-06-10). PATRA_LAUNCH_LOG.md / PATRA_FEAT_LOG.md not created yet by siblings (checked).
- .claude/settings.json DENIES Edit-tool on the 4 hot files → hot-file edits go ONLY via Python patcher in tmp/self_tests/. Never weaken deny rules.
- Prior session evidence base: PATRA_MEGA_REPORT.md (F1-F20 + H1-H11, all read), PATRA_BACKEND_RUN_LOG.md (read). All 7 proof scripts read in full this session.
- Proven baseline per operator prompt: harness 57/57, preflight 28/28, smoke 100/100, intents 128/128 (Genius-reported; local re-run attempted in Phase 1).

═══ SHARED RULES S1-S8 (verbatim — re-read after every compaction) ═══
S1 LANES — you may EDIT ONLY: the 4 hot files (sole owner), app/services/games/**, app/services/bella_rag/**
   and all intent/RAG/bella files, app/javascript/** + .vue + public/vite (sole owner), the 7 proof scripts
   in script/patra_*.rb. EVERYTHING ELSE IS READ-ONLY for you. TAB B owns non-hot services it names (AI fleet,
   FB services, jobs, models, specs, api/v1/accounts/patra/* controllers, Gemfile, config). TAB C owns
   app/views, app/dashboards, super_admin, db/migrate, features.yml. A needed edit outside your lane =
   write the exact file/line/diff into your log as HANDOFF-B or HANDOFF-C. Never just do it.
S2 GIT — stage+commit ONLY explicit paths: git add <your files> && git commit --no-verify -m "tabA: <msg>".
   NEVER git add -A, never add ., never commit -a — siblings have staged/untracked files you must not sweep.
S3 NEVER push/pull/rebase/stash/reset --hard (reset --hard DESTROYS sibling commits). Emergency undo of your
   own bad commit = git revert <hash> --no-edit, or fix forward. index.lock error = wait 30s, retry, x10.
S4 Red test? FIRST run git log --oneline -5 + git status. If a sibling committed in the last minutes, wait
   3 min and re-run once. If a sibling's committed change broke a check, adapt — never revert their commit.
S5 NEVER touch sibling logs (PATRA_LAUNCH_LOG.md, PATRA_FEAT_LOG.md) or owner-WIP files even if modified:
   telegram_notifier.rb, winback_service.rb, base_provider.rb, outbound_dispatcher.rb, zernio_provider.rb,
   PATRA_RUN_LOG.md.
S6 Local Rails/DB/Redis may NOT boot on this Windows machine — that is NOT a failure. Then: ruby -c every
   file + write the test/spec anyway + mark WALL-LOCAL-UNRUNNABLE in the log with the exact Render Shell
   commands for morning. Never fake a pass. Never revert work because the local env can't boot.
S7 NEVER ask, never idle — no human for 10h. Pick the SAFEST option, log it under ASSUMPTIONS, continue.
S8 Do not edit routes.rb or Gemfile or features.yml (B/C own them). Do not touch ANY secrets/.env/keys
   (TAB B handles secret-purge; operator owns rotation).

═══ MY HARD RULES A1-A5 (verbatim) ═══
A1 MONEY INVARIANTS ARE SACRED (already proven: harness 57/57, preflight 28/28, smoke 100/100, intents
   128/128). You may not weaken: (i) load counts only if panel confirmed; (ii) same payment can never load
   twice (deterministic order_id + unique index); (iii) Telegram always reports REAL remaining, $0 only when
   all confirmed; (iv) over-cap/approval paths never auto-execute; (v) no AI admission / no prompt leakage.
   After ANY money-adjacent edit: re-run the proof wall (or, if WALL-LOCAL-UNRUNNABLE, ruby -c + a focused
   spec + log "needs Render wall"). If a change would drop an assertion, revert YOUR change.
A2 HOT FILES (reply_service.rb, conversation_orchestrator.rb, intent_detector.rb, chatwoot_bridge_service.rb):
   one hot file per commit, view region before AND after each patch, ASCII-only edits, every external call
   begin/rescue, Telegram in safe_telegram, ruby -c after every edit.
A3 FRONTEND surgical only: if you edit .vue/app/javascript you MUST rebuild vite and commit public/vite/
   together with source in the SAME commit. Build fails or uncertain → revert the frontend change, log
   "UI gap — report-only (build risk)". Never leave half-built UI. Never stash pop.
A4 Production-grade only — no stubs, no placeholders, no TODO-and-skip in shipped code.
A5 Finish early? Do NOT invent features. Deepen the bug hunt, expand audits, re-verify. Idle-safe.

═══ TASK LEDGER (status: todo / in-progress / done / blocked / report-only) ═══

## PHASE 0 — LOAD STATE
- [x] Read PATRA_MEGA_REPORT.md, PATRA_BACKEND_RUN_LOG.md (PATRA_MASTER_COMPLETE.md absent — logged)
- [x] Read all 7 proof scripts in full
- [x] Create this log with ROLLBACK_HASH + rules verbatim
- [ ] Return shapes of things I'll touch (filled in per-task below as I read real code)

## PHASE 1 — BASELINE
- [x] WALL-LOCAL-UNRUNNABLE — `bundle exec rails runner` → "bundler: command not found: rails" (gems not installed locally; ruby 3.4.9 + bundler 2.6.9 present). Did NOT run bundle install (long, native-gem risk, Gemfile = TAB B lane). Proof mechanism this run: pure-Ruby self-tests in tmp/self_tests/ + ruby -c.
- [x] ruby -c baseline: all 7 proof scripts + all 4 hot files = Syntax OK (verified by me now, 2026-06-10).
- MORNING RENDER WALL (run in Render Web Shell, in order):
  bundle exec rails runner "puts 'boot ok'"
  bundle exec rails runner script/patra_money_harness.rb        # expect 57/57
  bundle exec rails runner script/patra_money_preflight.rb      # expect 28/28
  bundle exec rails runner script/patra_intent_suite.rb         # expect 128/128
  bundle exec rails runner script/patra_reply_smoke.rb          # expect 100/100 asserts
  bundle exec rails runner script/patra_rules_consistency_check.rb
  bundle exec rails runner script/patra_launch_readiness.rb
  bundle exec rails runner script/patra_balance_probe.rb

## PHASE 2 — BUG HUNT (failing-test-first, fix only in MY lane) — COMPLETE
- [x] payment OCR pipeline — read-verified sound (dup tiers txn-id+fingerprint, wrong-platform, recipient-mismatch, profile-page evidence, status buckets, false-load-claim guard). Report-only quirk: SCORE_ACTION=auto_load injection tells customer "loading it now" but guard_against_false_load_claim rewrites it unless a real load happened in 5min — safe direction, just means high-score messages read as "verifying with the bank".
- [x] load single/multi — F12 sites verified; BUG-2 found+fixed (5th site)
- [x] cashout — BUG-3 found+fixed (first-number parse); escalation flow sound
- [x] redeem/partial replay — BUG-3 fix covers; dedup window verified
- [x] transfer — forks/deposit_only/shortfall/dedup/velocity read-verified, cleared
- [x] freeplay — BUG-1 found+fixed (double GameAction, unflagged twin)
- [x] referral — BUG-4 found+fixed (username key; bonuses never paid)
- [x] chitchat/greeting — canned greeting + RAG shortcut + F-RAG cleared
- [x] account creation/reissue — silent-fail net verified (executor add_player get_user_id verify + 45s timeout + terminal codes); BUG-2 fixed
- [x] re-engagement/win-back — read-only (TAB B lane): ContactCooldown wired in all 3 senders (send_service:18, re_engage_job:38/45, winback_service:70/311). F19 >7d policy gap remains open per mega report — TAB B.
- [x] fraud guards — velocity/duplicate verified; HandleSelector accepts all 3 call shapes (*args/**kwargs) — false-alarm cleared; StatusNormalizer.needs_email_confirmation? exists.

## PHASE 3 — DEFINED FIXES
- [x] F-RAG: DONE — commit 03b0ec7f7. Map now 27 keys: 'greeting_chitchat' → :greeting (no orchestrator case branch → handle returns nil → LLM brain replies, verified), 'unclear' → nil (cutover treats nil as no-route, falls to LLM, cannot crash). Proof (b): tmp/self_tests/f24_rag_map_test.rb ALL PASS (10) — loads the REAL class in plain Ruby. Checker section 5 reads the live map, no change needed. Render: rules_consistency_check should print 27/27 mapped.
- [x] F-INBOX: VERIFIED CORRECT, report-only, no edit. (a) chatwoot_bridge_service.rb:387-413 — resolved_inbox_id = page-matched Channel::Api (fb_page_id join :429-438) → ENV id ONLY if Inbox.exists?(id, Channel::Api) → first Channel::Api on bridge account + WARN → raw ENV last resort; whole lookup rescued. Morning env flip to 28/29 will be honored as soon as it points at a real Channel::Api inbox.

## PHASE 4 — UI <-> BACKEND WIRING AUDIT → PATRA_UI_WIRING_AUDIT.md
- [x] DONE. ~70 controls audited across 8 settings areas. Results: everything WIRED except —
      Referral settings page was fully DECORATIVE → 4 of 6 fields WIRED-TONIGHT (commit 7aa71e219, kill-switch default OFF), 2 remain decorative (tracking_method, message texts);
      Patra Business Settings: webhook_url + first_response_limit_minutes + resolution_limit_minutes + sla_alerts_enabled are BACKEND-MISSING → HANDOFF-B-1/B-2 with exact diffs.
      IP-whitelist: verified Patra only DISPLAYS health (test_connection) — external whitelist correctly NOT claimed controllable.

## PHASE 5 — RE-PROOF (wall or S6 path after money-adjacent changes + once at end)
- [x] MID-RUN (after all code changes, 2026-06-10): INTENT SUITE 128/128 LOCAL GREEN (real detector via tmp/self_tests/h1_intent_suite_local.rb — verified by me now). ruby -c Syntax OK on all touched files (orchestrator, referral_bonus_service, harness). All 6 TAB A self-tests pass (f21-f26). Harness/preflight/smoke = WALL-LOCAL-UNRUNNABLE → exact Render commands in Phase 1 section; harness now includes TABA-1/2/3 sections proving tonight's fixes on real code.
- [ ] Final wall attempt at end of run

## PHASE 6 — AUDIT-ONLY
- [x] ROLES audit → PATRA_ROLES_AUDIT.md. CRITICAL (verified by me directly, agent_games_controller.rb:1-2,73,101): money endpoints load_player/cashout_player/add_player/reset_player_password have NO role guard — any agent can call them (caps + approval gate + audit trail still apply). NOTHING enforced tonight by design → HANDOFF-B-3 dark-flag diff written. Also unguarded: game_rules, player_tiers, reply_preferences (incl. confirm_before_cashout!), referrals#create/update, cashier_claims.
- [ ] BACKUP pages/connectors audit → PATRA_BACKUP_AUDIT.md (Explore agent running)
- [ ] AI MEMORY audit (agent running; verify claims before writing)

## PHASE 7 — MORNING SUMMARY (top of this file)
- [ ] Write 2-min readable summary + verdict

═══ ASSUMPTIONS ═══
(append as made)

═══ HANDOFF-B ═══

## HANDOFF-B-1: Patra SLA settings persisted but not consumed (app/jobs/sla/check_violations_job.rb — TAB B lane)
The settings page saves first_response_limit_minutes / resolution_limit_minutes / sla_alerts_enabled
into account.custom_attributes (patra/settings_controller.rb:83-85), but Sla::CheckViolationsJob reads
account.sla_policies + policy.first_response_time_threshold (check_violations_job.rb:28) and checks
sla_alerts_enabled NOWHERE — the three controls do nothing. Proposed diff (check_violations_job.rb):
```ruby
    def check_account(account)
      attrs = (account.custom_attributes || {}).stringify_keys
      # Settings -> "SLA alerts" toggle (default true when unset)
      return if attrs.key?('sla_alerts_enabled') && ActiveModel::Type::Boolean.new.cast(attrs['sla_alerts_enabled']) == false

      policies = account.sla_policies
      ...
    def check_first_response(conversation, policy)
      attrs = (conversation.account.custom_attributes || {}).stringify_keys
      threshold_minutes = (attrs['first_response_limit_minutes'].presence || policy.first_response_time_threshold).to_f
```
resolution_limit_minutes has no check at all (job only checks first response) — either add a
check_resolution mirror or remove the field from the UI.

## HANDOFF-B-2: webhook_url (Patra Business Settings) is test-only
account.custom_attributes['webhook_url'] is only ever POSTed by the controller's test_webhook
(patra/settings_controller.rb:42-67). No listener emits real events to it (webhook_listener.rb
uses inbox.channel.webhook_url). Decide: emit conversation/payment events to this URL via a
listener, or drop the field from the settings UI. Until then it is BACKEND-MISSING.

## HANDOFF-B-3: role guards for money endpoints (agent_games_controller.rb + siblings — TAB B lane)
See PATRA_ROLES_AUDIT.md for the full table + exact dark-flag diff (PATRA_RESTRICT_MONEY_ACTIONS,
default OFF). Do NOT apply live tonight — operator decision in the morning.

═══ HANDOFF-C ═══
(exact file/line/diff for TAB C-owned fixes)

═══ REVERTED ═══
(none)

═══ BUG LOG (flow / symptom / root cause / fix commit / proof) ═══

## BUG-1 (HIGH, money) — freeplay/bonus loads double-recorded; freeplay counted as REAL deposit
Flow: freeplay + bonus load. Evidence (a, read-verified): ActionExecutor#load_player ALWAYS creates the audit GameAction (action_executor.rb:100-113); handle_load_freeplay (orchestrator:648-668) and handle_load_bonus (:786-811) then create a SECOND manual GameAction for the same recharge. The executor's record has metadata {source: 'bella_orchestrator'} with NO freeplay flag, so:
  (1) every freeplay/bonus load is counted twice in total_deposits (cashout multiplier math :914-933 inflated);
  (2) the unflagged executor record makes freeplay money look like a real deposit — original_deposit_on_source (:2670-2681, deposit-only transfer) can "return" the freeplay amount as the player's deposit;
  (3) freeplay_require_deposit_first check (:617-623) is satisfied by a prior freeplay's unflagged twin.
Fix: thread metadata through execute_game_api into load_player; delete both manual GameAction.create! blocks. Plus deterministic order_id for the bonus payment load (same F12 class).
Status: DONE — commit 6497ee553. Proof (b): tmp/self_tests/f22_freeplay_double_record_test.rb ALL PASS (12) — failing-first confirmed (6 FAIL pre-patch), ruby -c OK. Harness TABA-1 cases added (commit 9ba549418). Needs Render wall.

## BUG-2 (HIGH, money) — F12 gap: account-creation-with-payment load can double-load the same payment
Flow: account creation with confirmed payment. Evidence (a): orchestrator:1246-1251 calls executor.load_player with NO order_id (random) and no IdempotencyError rescue — the 5th automated payment-load site, missed by F12 (which fixed the other 4). Two concurrent "create me an account" messages with one confirmed payment → both pass payment_already_loaded? (check-then-act) → double-load.
Fix: mirror F12 — deterministic_payment_order_id(recent_payment[:id]), nil → already-loaded reply (with the fresh credentials), rescue IdempotencyError/RecordNotUnique.
Status: DONE — commit ff1b2add2. Proof (b): tmp/self_tests/f21_account_create_orderid_test.rb ALL PASS (7) — failing-first confirmed (3 FAIL pre-patch), ruby -c OK. Harness TABA-2 cases added (9ba549418, corrected 85c708d28 to drive the TRUE race: winner row invisible to legacy check-then-act). Needs Render wall.

## BUG-3 (MED, money) — cashout amount parsed as FIRST number in message
Flow: cashout + redeem-partial-replay. Evidence (a): handle_cashout_intent :906-909 and handle_redeem_partial_replay :3003-3004 scan the raw text and take the FIRST number, ignoring the detector's verb-adjacent amount. "keep 30 in and cash out 50" → cashes out $30 (redeem-partial actually moves the wrong amount via cashout_player; cashout intent reports wrong amount to cashier Telegram).
Fix: prefer intent[:amount] (cashout), else the number right after a cashout verb, else legacy first-number.
Status: DONE — commit 1b82031de. Proof (b): tmp/self_tests/f23_cashout_amount_test.rb ALL PASS (13) incl. all 3 existing harness phrasings unchanged; failing-first confirmed (3 FAIL pre-patch), ruby -c OK. Harness TABA-3 cases added (9ba549418). Needs Render wall.

## BUG-4 (MED, money) — referral freeplay bonuses silently NEVER paid
Flow: referral. Evidence (a): referral_bonus_service.rb:95 read custom_attributes["#{game_slug}_username"] (e.g. 'juwa_username') but the codebase writes 'game_username_<slug>' (orchestrator store_game_username :1680) → username always nil → return before any load. Also preferred_platform vault values ('milkyway') never mapped to slugs, and the fallback AgentGame picked ANY game including inactive panels.
Fix: use game_username_<slug> key; map via PREFERRED_PLATFORM_TO_SLUG; consider only active agent_games, preferring the player's preferred slug, else first active game where the player actually has a username.
Status: DONE — commit ef8a682e7. Proof (b): tmp/self_tests/f25_referral_bonus_username_test.rb ALL PASS (8), failing-first confirmed (4 FAIL pre-fix), ruby -c OK. NOTE: this makes referral auto-pay LIVE for the first time (it could never fire before). Pays $5+$5 freeplay via the normal capped/blacklist-guarded executor path after referred player's first deposit. If operator prefers it stay dormant on launch day, revert ef8a682e7.

## BUG-5 (LOW, latent) — RAG-shortcut QuickRephrase still called retired Grok/xAI
Flow: chitchat RAG shortcut (BELLA_RAG_SHORTCUT_ENABLED, currently flag-off). Evidence (a): quick_rephrase.rb posted to Ai::ReplyService::XAI_URL with XAI_API_KEY — Batch C retired Grok (credits exhausted), so enabling the flag could never produce a reply (nil → fallthrough; fail-closed but feature dead).
Fix: route through shared Ai::DeepseekClient.complete (TAB B's hardened client — called, not edited), max_tokens 800 (mirrors live path; low values starve flash reasoning+answer). Fail-closed semantics + persona prompt unchanged.
Status: DONE — commit 06c896a92. Proof (b): tmp/self_tests/f27_quick_rephrase_deepseek_test.rb ALL PASS (9), failing-first confirmed (3 FAIL pre-fix), ruby -c OK.

## Phase-2 candidates examined and CLEARED (no bug):
- handle_username_provided / handle_load_intent: F12 order_id + rescue present at all 4 sites (read-verified :415-427, :464-477, :1031-1043, :1076-1088).
- transfer loads: random order_id but the whole flow is gated by recent_cashout_duplicate? on the cashout side (:2406-2409) — single-funding protected.
- complete_pending_transfer_create: pending flag cleared BEFORE execution (:2756) so a second "yes" can't re-trigger; narrow same-instant race accepted (funded by one already-done cashout).
- velocity guard, duplicate-payment guard: present and fail-safe direction verified (:867-878, :398-408).
- chosen_game_slug falls back to 'game_vault' (:1480) — makes the "which game?" branches in status/balance handlers unreachable; UX-only, not money. Report-only.

═══ WORK LOG (append-only, newest at bottom) ═══
- 2026-06-10 Phase 0 complete: rollback hash captured, rules copied, all state files + 7 scripts read.
