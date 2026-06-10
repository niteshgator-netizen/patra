# PATRA BACKEND MEGA v2-FINAL — REPORT
Date: 2026-06-09 · Session: backend Claude Code (coexisted with UI session)
ROLLBACK_HASH=495a02cae47747975e3fcf1e282ea3635cdbe8b7
All work is LOCAL COMMITS ONLY — operator pushes once after review.
Evidence labels: (a) read-verified file:line · (b) self-test-proven · (c) needs-Render-proof.

## 1. PER-FIX STATUS (Phase 1 — all 20 done)

| Fix | Commit | What | Proof |
|-----|--------|------|-------|
| F1 re-engage shared cooldown | 069054220 | NEW Reengagement::ContactCooldown (custom_attributes last_automated_contact_at, ENV PATRA_REENGAGE_COOLDOWN_HOURS=24 read at send-time) checked+stamped by ReEngageJob, SendService/DormantPlayerJob, WinbackService; dormant job 10:00→12:00 | (a)+(b) f1 test ALL PASS (loads REAL module) |
| F2 shift report crash | b93b1779f | :33 called PRIVATE keyword-only Games::TelegramNotifier.notify positionally (NOT Audit:: as briefed) → new public shift_report(account:, text:) plain + per-account rescue | (a)+(b) |
| F3 expire claims crash | 67c8e0ec2 | same crash EVERY MINUTE; crash aborted find_each → later claims never expired. Public claim_available + rescue so alerts can't block expiry | (a)+(b) repro showed expired=[1] of 3 |
| F4 webhook HMAC | 12eece35e | X-Hub-Signature-256 of raw body (FB_APP_SECRET env→GlobalConfig, MetaTokenVerifyConcern construction), LOG-ONLY default + redis daily counter, 401 only when PATRA_ENFORCE_WEBHOOK_SIGNATURE=true | (a)+(b) RFC 4231 vector |
| F5 freshness gate | 45d99a65c | [HOT reply_service] @latest_timestamp was Time.current → gate :337-341 permanently no-op; now max incoming created_at | (a)+(b) fresh/stale/empty/boundary |
| F6 summary Array crash | 453976f2f | iteration assumed Message; flatten+respond_to? guard; exact live error string reproduced; in-repo callers all pass Messages (producer not in repo — noted) | (a)+(b) |
| F7 already-exists reuse | 963cd5a4e | documented codes only: GameVault-family 20, FastApi-family 12 (FastApi 20 = PASSWORD error — families must not share!); get_user_id-verified then success-reuse + reused_existing flag; ambiguous keeps escalating | (a)+(b) 6 checks |
| F8 clientless deactivator | 41181bf35 | script plan-first/--confirm/idempotent vs ClientRegistry slugs | (b)+(c) run on Render |
| F9 payment_info WARN | c617d433f | [HOT reply_service] no seeding pattern exists → live-PaymentHandle fallback (priority+cooldown aware, cached 600s); WARN only when neither exists | (a)+(b) |
| F10 smoke raw_field | cafbc2798 | label now mirrors content-first parser (reply_service.rb:2114-2116) | (a)+(b) |
| F11 bridge inbox fallback | 37fafc442 | [HOT chatwoot_bridge_service] ENV inbox honored only if exists+Channel::Api → else first Channel::Api on account + WARN → else ENV passthrough; readiness FAIL lists available inboxes | (a)+(b) live-shaped fixture |
| F12 load race | 741d5a44e | [HOT orchestrator] deterministic order_id pay+SHA1(account:contact:payment)[0,20], _a<n> attempt suffix; success/pending blocks; IdempotencyError/RecordNotUnique → already-loaded reply at all 4 load sites. UNIQUE INDEX PROVEN pre-existing (20260513030000:29; schema.rb stale at 2026_05_07) → migration skipped | (a)+(b)+harness F12 cases (c) |
| F13 auto-load cap | a428a2a96 | VERIFIED enforced (action_executor.rb:71-72 sole funnel) — NO code change; harness drives real handle_load_intent capped/uncapped | (a)+harness (c) |
| F14 FB error 190 | 6b47adfb1 | loud log + api_error telegram throttled 1/hr/page (setex TTL 3600). Auto-refresh NOT implemented (see §4) | (a)+(b) |
| F15 approval auto-resume | a4eca89a6 | DARK behind PATRA_APPROVAL_AUTORESUME: model after_update_commit → AutoResumeJob → AutoResume.execute! exactly-once via order_id appr_<id>; executor skip_approval_gate kwarg (no re-gate loop); reject never; failure → cashout-group telegram REAL state | (a)+(b) 7 checks + harness 8 cases (c) |
| F16 takeover pause | 8307296ec | [HOT reply_service] outgoing non-private non-ai_auto = human → pause PATRA_TAKEOVER_PAUSE_MINUTES (default 0=off); ai-off untouched | (a)+(b) |
| F17 stuck-pending alert | 61f947f1b | GameActions pending >1h → telegram per account (ids+amounts), 1/hr setex throttle, zero mutation | (a)+(b) |
| F18 blank balances | 29f14bef2 | DIAGNOSIS: Juwa reads only data.agent_balance (juwa/client.rb:147, nil on key drift); PandaMaster regex /Balance:([\d.]+)/ can't match thousands-separators/markup drift (asp_net_panel:200-204). Fix needs live bytes → script/patra_balance_probe.rb captures them | (a)+(c) run probe |
| F19 winback FB policy | report-only | tag pipeline EXISTS+WIRED on live zernio path (winback flag → SendApiService:91-106 → OutboundDispatcher:28-29 → ZernioProvider:24-27). The #10 failures come from ReEngageJob + DormantPlayerJob targeting >7d where NO tag is valid — see §4 | (a) |
| F20 ReplyJob retries | b7476b86b | retry_on StandardError 3 / TransientSendError 5, polynomial, loud give-up (was Sidekiq default 25) | (a)+(b) |

## 2. PER-H VERDICTS (Phase 2)

- **H1 INTENT** (commit eff5a12ae): script/patra_intent_suite.rb — 128 golden cases, **128/128 pass**. Two suite-proven detector fixes [HOT intent_detector]: (1) greeting no longer steals money intents ("hey can i load 20" was :greeting); (2) \b stops username-tail digits parsing as amounts ("im slickrick7 on juwa" was **load $7**). Known overlap documented, not fixed: "referral bonus"→load_bonus (branch order).
- **H2 RAG**: OK — scoping account+NULL (bella_rag_pair.rb:17-23), .to_a workaround in both paths (intent_retriever.rb:38,:81), exactly-0.40 ROUTES (>= at orchestrator:209), Voyage-down fully rescued (nil/[]). RAG_TO_INTENT_MAP now 25 labels (CLAUDE.md "16/27" is stale); checker §5 prints any unmapped DB labels. Checker: script/patra_rules_consistency_check.rb (commit ec6beeaee).
- **H3 MEMORY**: slicing OK (.last(50)); rotation bounded (trigger 1000, fold 500/run); memory_enabled checked on read (reply_service:~1578) AND write (rotate job:46-50). FIXED: profile/memory block was uncapped into prompt → PLAYER_PROFILE_MAX_CHARS=6000 cap (commit af600ee77). RISK (report-only): PlayerMemoryWriter parse takes the single DeepSeekClient string (content-first); a content-prose + reasoning-JSON response loses the JSON (player_memory_writer.rb:142-143).
- **H4 HANDLES**: HandleResolver is OCR-side; prompt-side handle comes from HandleSelector hint (reply_service build_system_prompt:1992-1995) + payment_info canned/F9 fallback. Stale-handle contradictions now detectable via the checker (canned/GameRule/RAG-pairs vs active handles — the $sofiamann8 class traces to stale text in those sources, surfaced by sections 2-4).
- **H5 MONEY WALK**: confirm_before_cashout checked, no bypass; >$500 gate at executor only (orchestrator never bypasses; F15 bypass is explicit + post-approval); reissue moves $0; deposit_only/shortfall enforced with [amount, balance].min; no unrescued external calls in money handlers. RISK (report-only): transfer-plan extraction shares the content-first single-string risk as H3 writer (orchestrator:2543-2552). NOTE: AgentGame.failure_count consumed via status auto-flip (inactive@5/degraded@3) which pick_agent_game honors — wired, not write-only.
- **H6 CLIENTS**: 14 clients, 3 families. JSON family (GameVault/Juwa/FastApi): data.agent_balance/user_balance. ASP.NET (MilkyWay/FireKirin/PandaMaster/OrionStars): HTML scrape + sanitize_panel_name [A-Za-z0-9_]{13} + whole-dollar amounts. Laravel (Mafia/GameRoom/CashMachine/MrAllInOne): message-string errors, remark stripped to alnum[50]. Already-exists: GV-family 20, FastApi 12, Juwa 20; Laravel/ASP.NET message-based (left escalating by design). check_balance net on add_player present (executor player_exists_after_create?).
- **H7 INTAKE**: sound. /bot (HMAC log-only) → FacebookBridgeJob (mid SET-NX 24h :91-94 + sender mutex 30s :32-36, release_mid on failure so retries re-claim) → ChatwootBridgeService (page_id→inbox→token; F11 fallback) → ReplyJob (reply lock 30s). Image: confidence gate high|medium only (reply_service:943) + keyword override to medium (:221); finance log append w/ 24h duplicate flagging.
- **H8 REPLY GATES — the "AI is silent" debug checklist (ordered):**
  1. ReplyJob: blacklist → canned restricted reply instead
  2. ReplyJob: reply lock patra:reply_lock:conv:<id> (30s) → duplicate skip (image OCR still runs)
  3. DEEPSEEK_API_KEY blank → nil
  4. CHATWOOT_BRIDGE_API_TOKEN blank → nil
  5. secret phrase pause_ai_and_notify → nil
  6. freshness gate (F5): latest incoming >10 min → nil  ← NEWLY LIVE
  7. no usable history → nil
  8. ai-off label → nil
  9. human-takeover pause (F16, PATRA_TAKEOVER_PAUSE_MINUTES>0) → nil  ← NEW
  10. sender-match flow / money intents → orchestrator (telegram instead of LLM on holds)
  11. LLM empty/leak-trimmed reply → nil ("job finished without sending")
  Then outbound: PSID missing, FB token dead (190 — now alerts, F14), provider errors.
- **H9 PERSONA**: smoke V2 (commit 9c9b1d82c) — 27 scenarios + leakage assertions. (c) needs Render run.
- **H10 JOBS/INFRA**: every schedule.yml class exists; every queue_as is in sidekiq.yml (91 jobs / 16 queues); DB pool = SIDEKIQ_CONCURRENCY(10) on worker, ≥ puma threads(2) on web — OK; rack_attack 3000 req/ip/min — no /bot risk; ALL new redis keys TTL'd (7d/1h/1h verified post-fix).
- **H11 BLAST RADIUS**: prompt_chars log line added (af600ee77). No unrescued external calls in live money paths (H5). DeepSeek retry-storm killed by F20. build_messages is one HTTP call (no N+1); winback per-contact history query is daily-job scoped — acceptable.

## 3. DAY-1 RISK TABLE

| Risk | Severity | State |
|------|----------|-------|
| Same payment double-load under concurrency | HIGH | FIXED (F12) — needs harness green on Render |
| Expire-claims crash blocking expiries every minute | HIGH | FIXED (F3) |
| FB token death = silent outage | HIGH | ALERTED (F14); refresh still manual |
| Bridge ENV points at deleted inbox 5 | HIGH | AUTO-FALLBACK (F11); still fix ENV to 28/29 |
| ReEngage/Dormant jobs send policy-violating >7d FB messages (#10) | MED | OPEN (report §4) — consider disabling crons until reworked |
| Juwa/PandaMaster blank balances | MED | DIAGNOSED; run probe, then one-line fix |
| Stale handles quoted from canned/RAG text | MED | DETECTABLE — run checker, clean offenders |
| Memory/transfer parse loses reasoning-field JSON | LOW | OPEN (§4) |
| Stale conversations replied to | LOW | FIXED (F5) |

## 4. REPORT-ONLY FINDINGS (proposed, NOT applied)

1. **F19 re-engagement policy**: In Reengagement::SendService#call + ReEngageJob#send_reengage, branch on last-incoming age: ≤7d → create message with additional_attributes {'winback'=>true} (rides existing HUMAN_AGENT pipe); >7d → Games::TelegramNotifier.winback_manual_alert + private note (WinbackService :119-136 pattern). Policy risk: HUMAN_AGENT on automated outreach is gray-zone; volume tagging may hurt page quality.
2. **F14 auto-refresh**: wire Patra::RefreshFbTokensJob trigger on first 190 alert per page (job exists, cron weekly Sunday 03:00).
3. **F7 password caveat**: on reused_existing, the orchestrator may message a slug-derived password that's wrong for the sibling-skin account. Proposed: when add_result[:reused_existing], call executor.reset_player_password before messaging credentials, or omit the password line.
4. **H3/H5 content-vs-reasoning JSON**: DeepseekClient.complete returns ONE string (content-first). For JSON consumers (PlayerMemoryWriter :142, transfer plan :2543-2552), prefer the field that CONTAINS JSON: try content, and when no JSON found, retry extraction on raw reasoning_content (needs DeepseekClient to expose both fields or a raw mode).
5. **F6 producer**: the Array-shaped caller isn't in the repo; if 'Summary unavailable' recurs on conv 111 after deploy, capture the controller path from logs.
6. **H1 'referral bonus'** routes to load_bonus (BONUS before REFERRAL). Reordering is not zero-regression-safe; revisit with more golden rows.
7. **schema.rb is stale** (version 2026_05_07; lacks game_actions etc.). Run `bundle exec rails db:schema:dump` on Render and commit, or future migration work will diff badly.

## 5. ENV KNOBS ADDED (all default-safe)

| Var | Default | Effect |
|-----|---------|--------|
| PATRA_REENGAGE_COOLDOWN_HOURS | 24 | shared automated-contact cooldown window (0/garbage→24) |
| PATRA_ENFORCE_WEBHOOK_SIGNATURE | off | true → 401 invalid X-Hub-Signature-256 (else log+count) |
| PATRA_TAKEOVER_PAUSE_MINUTES | 0 (off) | minutes AI stays quiet after a human agent replies |
| PATRA_APPROVAL_AUTORESUME | off | true → approving a cashout executes it exactly once |

## 6. RENDER VERIFICATION SEQUENCE (run in order, Web Shell unless noted)

```
# 0. sanity
bundle exec rails runner "puts 'boot ok'"

# 1. crashes fixed
bundle exec rails runner "Cashier::ExpireClaimsJob.new.perform; puts 'expire ok'"
bundle exec rails runner "Reports::ShiftReportJob.new.perform; puts 'shift ok'"
bundle exec rails runner "puts Ai::ConversationSummaryService.new(Conversation.find(111).messages.where.not(content: [nil,'']).order(:created_at).limit(50)).call"

# 2. money + approval (stubbed, $0)
bundle exec rails runner script/patra_money_harness.rb        # incl F12/F13/F15 sections
bundle exec rails runner script/patra_money_preflight.rb

# 3. intent + persona
bundle exec rails runner script/patra_intent_suite.rb         # expect 128/128
bundle exec rails runner script/patra_reply_smoke.rb          # 27 scenarios (real DeepSeek)

# 4. consistency + readiness + balance evidence
bundle exec rails runner script/patra_rules_consistency_check.rb
bundle exec rails runner script/patra_launch_readiness.rb
bundle exec rails runner script/patra_balance_probe.rb        # paste output back for F18 fix

# 5. clientless games (plan first, then confirm)
bundle exec rails runner script/patra_deactivate_clientless_games.rb
bundle exec rails runner script/patra_deactivate_clientless_games.rb --confirm

# 6. bridge fallback (expect 28/29 + WARN, not 5)
bundle exec rails runner "svc=Facebook::ChatwootBridgeService.allocate; svc.instance_variable_set(:@page_id,'nope'); puts svc.send(:resolved_inbox_id)"

# 7. after green: fix CHATWOOT_BRIDGE_INBOX_ID env to a real Channel::Api inbox.
# Both services (Web + Worker) must go green after deploy.
```

## 7. SCRIPTS (all parse-verified)
patra_money_harness.rb (F12/F13/F15 added) · patra_money_preflight.rb (untouched, verified) · patra_reply_smoke.rb (V2, 27 scenarios) · patra_launch_readiness.rb (F11 inbox listing) · patra_intent_suite.rb (NEW) · patra_rules_consistency_check.rb (NEW) · patra_deactivate_clientless_games.rb (NEW) · patra_balance_probe.rb (NEW)
