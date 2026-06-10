# PATRA BACKEND MEGA v2-FINAL — RUN LOG (state file)

OWNER: backend Claude Code session (this file). Parallel session owns PATRA_RUN_LOG.md — never touch it.
ROLLBACK_HASH=495a02cae47747975e3fcf1e282ea3635cdbe8b7
STARTED: 2026-06-09
NOTE: PATRA_MASTER.md does NOT exist (checked). PATRA_MEGA_REPORT.md will be created in Phase 3.
NOTE: .claude/settings.json DENIES Edit-tool on the 4 hot files → hot-file edits go ONLY via Python patcher in tmp/self_tests/ (R1). Never weaken deny rules.
NOTE: PATRA_SYNC.md "DO NOT accept bulk tasks" conflicts with this run's explicit operator prompt — operator prompt wins; logged here.

═══ COEXISTENCE (verbatim — survives compaction) ═══
C1 You own ONLY: app/services/**, app/jobs/**, app/controllers/webhooks/**, app/models/** (additive), lib/**, config/schedule.yml, config/initializers (additive), db/migrate (new files), script/**, tmp/self_tests/**, PATRA_BACKEND_RUN_LOG.md, PATRA_MEGA_REPORT.md. NEVER touch: .vue/.js/.jsx/.scss/.css, public/**, app/javascript/**, package.json, vite configs, PATRA_RUN_LOG.md. Frontend bugs → report only.
C2 Before EVERY edit: git status --short <file>. A file you own showing changes you didn't make = the other session — SKIP, queue retry in 30 min, log the collision.
C3 Commits: one per fix, git add <explicit paths you edited only> (never -A). On index.lock failure: sleep 20s, retry up to 10x.
C4 NEVER: push, pull, rebase, stash, branch-switch, reset. Local commits only; the operator pushes once at the end.

═══ RULES (verbatim — survives compaction) ═══
R1 HOT FILES (app/services/ai/reply_service.rb ~2800, app/services/games/conversation_orchestrator.rb ~3300, app/services/games/intent_detector.rb, app/services/facebook/chatwoot_bridge_service.rb): read the full surrounding region first; edit via a Python patcher file in tmp/self_tests/ with assert-one-match per edit; write the patcher ASCII-safe (escape em-dashes/unicode as byte literals — a previous run's heredoc silently applied ZERO edits because of a literal em-dash); CRLF/no-BOM preserved; ruby -c after every edit; ONE hot file per commit; RE-READ the patched region afterward to confirm the edit actually landed.
R2 MONEY: implement ONLY the money changes in F12/F13/F15/F17. Any other money-behavior idea → report with file:line + proposed diff, never apply. Money invariants to assert in harness cases after every money change: (i) funds decrement only on confirmed per-target success (ii) Telegram always reports REAL remaining state (iii) same order_id never executes twice (iv) failed targets escalate needs-human (v) nothing auto-executes above a set cap.
R3 Every fix ships executable proof: pure-Ruby replica self-test in tmp/self_tests/ (run it, paste output into the log) AND/OR new cases in the Render scripts (script/patra_money_harness.rb, patra_money_preflight.rb, patra_reply_smoke.rb, patra_launch_readiness.rb). All four stay runnable; whatever you change gains coverage.
R4 No production network calls, no DB access from this machine. Live-data needs → write a Render-run script (rails runner; read-only, or writes gated behind an explicit --confirm flag; idempotent; prints its plan first).
R5 Evidence labels on every report claim: (a) read-verified file:line (b) self-test-proven (c) needs-Render-proof (exact command). Never claim fixed without (a)+(b).
R6 Debug discipline: suspected bug → FIRST write a failing self-test reproducing it from the real code's logic → THEN fix → THEN show it passing. No fix without reproduction.
R7 Self-audit every ~10 fixes AND at the end: ruby -c every touched .rb; ruby -ryaml -e 'YAML.load_file("config/schedule.yml")'; git log --oneline since ROLLBACK_HASH (clean per-fix commits, zero frontend files); git status clean of your files; update the run log.
R8 Stubs for anything send/money-shaped in test scripts: stub_singleton save+restore in ensure, money intents print would-route SKIPPED, Telegram recorded never sent (mirror patra_money_harness.rb / patra_reply_smoke.rb patterns).

═══ QUEUE (status: todo / in-progress / done / blocked / report-only) ═══

## PHASE 1 — FIXES
- [x] F1 Re-engagement shared cooldown — done (commit 069054220)
- [x] F2 shift_report_job.rb:33 TelegramNotifier positional-call crash — done (commit b93b1779f)
- [x] F3 expire_claims_job.rb:19 same crash every minute; rescue around notify — done (commit 67c8e0ec2)
- [x] F4 bot_controller HMAC — done (commit 12eece35e)
- [x] F5 freshness gate revived — done (commit 45d99a65c)
- [x] F6 conversation_summary_service Array crash — done (commit 453976f2f)
- [x] F7 already-exists success-reuse — done (commit 963cd5a4e)
- [x] F8 deactivate-clientless script — done (commit 41181bf35)
- [x] F9 payment_info fallback — done (commit c617d433f)
- [x] F10 smoke raw_field label — done (commit cafbc2798)
- [x] F11 bridge inbox fallback — done (commit 37fafc442)
- [x] F12 deterministic order_id — done (commit 741d5a44e; migration SKIPPED, unique index proven pre-existing)
- [x] F13 cap verified enforced + harness — done (commit a428a2a96, no code change)
- [x] F14 FB error 190 alert — done (commit 6b47adfb1)
- [x] F15 approval auto-resume dark — done (commit a4eca89a6)
- [x] F16 human-takeover pause — done (commit 8307296ec)
- [x] F17 stuck-pending sweeper alert — done (commit 61f947f1b)
- [x] F18 balance probe script + report-only diagnosis — done (commit 29f14bef2)
- [x] F19 REPORT-ONLY (tag mechanism already wired on live path; >7d senders can't be tagged) — done
- [x] F20 ReplyJob bounded retries — done (commit b7476b86b)

## PHASE 2 — ADVERSARIAL HUNT
- [ ] H1 intent golden suite script/patra_intent_suite.rb — todo
- [ ] H2 RAG runtime path + script/patra_rules_consistency_check.rb — todo
- [ ] H3 memory window/writer/rotation/caps — todo
- [ ] H4 payment HandleResolver consistency — todo
- [ ] H5 money walk read-only — todo
- [ ] H6 14 game clients taxonomy — todo
- [ ] H7 intake pipeline trace — todo
- [ ] H8 reply gates ordered list post-F5/F16 — todo
- [ ] H9 persona red-team V2 scenario suite ≥20 — todo
- [ ] H10 jobs+infra re-verify, pools, rack_attack, TTLs — todo
- [ ] H11 blast radius + perf report — todo

## PHASE 3 — OUTPUT
- [ ] PATRA_MEGA_REPORT.md committed — todo
- [ ] All scripts runnable — todo
- [ ] Final console summary — todo

═══ COLLISION LOG ═══
(none yet)

═══ FIX LOG (per-item evidence) ═══

## F2 — DONE (commit b93b1779f)
Bug (a, read-verified): app/jobs/reports/shift_report_job.rb:33 called Games::TelegramNotifier.notify(account, message) — notify is PRIVATE (telegram_notifier.rb:147) and keyword-only (:149) → NoMethodError every run. (Prompt said Audit::TelegramNotifier; actual callee read-verified as Games::TelegramNotifier.)
Fix: new public Games::TelegramNotifier.shift_report(account:, text:) → notify(event: EVENT_SHIFT_REPORT, plain: true) [plain because report text has MarkdownV2-unsafe $/()/-]; job rescues per-account so one failure can't stop other accounts. NotificationChannel#should_notify? defaults TRUE for unknown events (notification_channel.rb:45) so new event delivers out of the box.
Proof (b, self-test-proven): tmp/self_tests/f2_shift_report_notify_test.rb →
  REPRO OK: pre-fix call shape raises NoMethodError (private method 'notify'...)
  FIX OK / FILTER OK x2 / F2 SELF-TEST: ALL PASS
Needs-Render-proof: bundle exec rails runner "Reports::ShiftReportJob.new.perform" (expect telegram message, no exception).

## F3 — DONE (commit 67c8e0ec2)
Bug (a, read-verified): app/jobs/cashier/expire_claims_job.rb:19 same private/positional crash, queue low, scheduled every minute. WORSE: crash aborts find_each → current claim DID expire (expire! runs first) but all later claims in the batch never expire that run.
Fix: public Games::TelegramNotifier.claim_available(account:, text:) (plain, default-on event) + rescue StandardError in notify_cashiers so alert failure can never block expiry.
Proof (b): tmp/self_tests/f3_expire_claims_test.rb →
  REPRO OK: NoMethodError after first claim; expired=[1] (claims 2,3 NEVER expired)
  FIX OK: telegram down, all 3 expired=[1,2,3], 3 rescued failures logged
  F3 SELF-TEST: ALL PASS
Needs-Render-proof: bundle exec rails runner "Cashier::ExpireClaimsJob.new.perform"
NOTE: tmp/ is gitignored — self-tests live on disk + output pasted here (R3 satisfied via log).

## F6 — DONE (commit 453976f2f)
Bug (a): app/services/ai/conversation_summary_service.rb:13-16 iteration assumed every element is a Message; Array() coercion in initialize turns a Hash into [k,v] Array pairs and any grouped/sliced input keeps nested Arrays → exact live error "undefined method 'outgoing?' for an instance of Array" → rescue returned 'Summary unavailable' on every call.
Root-cause caveat (c/assumption): both in-repo callers (patra/conversation_summary_controller.rb:8, captain/tasks_controller.rb:47) pass Message records — read-verified; no enterprise override (prepend_mod target absent). The Array-producing caller is NOT in the repo (console invocation or stale deploy likely). Fix makes the service shape-tolerant regardless.
Fix: flatten + respond_to?(:outgoing?) filter_map; normal-path output byte-identical (proven).
Proof (b): tmp/self_tests/f6_summary_array_test.rb → REPRO OK x2 (grouped + hash both hit exact live error string), FIX OK x4, ALL PASS.
Needs-Render-proof: bundle exec rails runner "puts Ai::ConversationSummaryService.new(Conversation.find(111).messages.where.not(content: [nil,'']).order(:created_at).limit(50)).call"

## F1 — DONE (commit 069054220)
Bug (a): three independent automated senders with NO shared guard — ReEngageJob (AuditLog 30d only, re_engage_job.rb:28-32), DormantPlayerJob→SendService (last_reengagement_date 14d, send_service.rb:53-61), WinbackService (winback_last_contacted_at per-tier, winback_service.rb:66-67). One contact could get 3 automated messages in a day.
Fix: app/services/reengagement/contact_cooldown.rb (NEW, near-plain Ruby so self-test loads the REAL file): custom_attributes['last_automated_contact_at'] (codebase's contact-flag pattern), ENV PATRA_REENGAGE_COOLDOWN_HOURS default 24 read at SEND-TIME, 0/garbage→24 (guard can't self-disable). Checked+stamped in: re_engage_job.rb send_reengage (check before conv lookup, stamp after send), send_service.rb (skipped(:automated_contact_cooldown) + merged stamp in record_reengagement_timestamp!), winback_service.rb (check after winback stamp check :66, merged stamp in stamp_contacted!). schedule.yml: dormant 10:00→12:00 (stagger 08/09-log/12/17; winback kept 17:00, log-only kept 09:00). YAML validated.
Proof (b): tmp/self_tests/f1_contact_cooldown_test.rb (loads REAL module) → REPRO OK (2 senders unguarded pre-fix), FIX OK x6 incl. send-time ENV read + 23h/25h boundary + 17:00→08:00 block scenario. ALL PASS.
ENV knob: PATRA_REENGAGE_COOLDOWN_HOURS (default 24).
Needs-Render-proof: bundle exec rails runner "c=Contact.find(<id>); puts Reengagement::ContactCooldown.on_cooldown?(c)"

## F4 — DONE (commit 12eece35e)
Bug (a): webhooks/bot_controller.rb POST /bot had ZERO signature verification (read-verified full file pre-edit) — anyone could POST forged page events.
Fix: X-Hub-Signature-256 = sha256-prefixed HMAC of request.raw_post, same construction as MetaTokenVerifyConcern:35-36 (secure_compare). Secret: ENV FB_APP_SECRET then GlobalConfigService.load('FB_APP_SECRET') — messenger_controller.rb:70 pattern. LOG-ONLY default (warn + redis daily counter patra:webhook:invalid_signature:YYYYMMDD, 7d TTL); 401 only when PATRA_ENFORCE_WEBHOOK_SIGNATURE=true. Blank secret → skipped (never bricks intake). Internal errors fail OPEN with loud log. GET hub.challenge untouched.
Proof (b): tmp/self_tests/f4_webhook_hmac_test.rb → VECTOR OK (RFC 4231 case 2), SIG OK x3, MODE OK x4, ALL PASS.
ENV knob: PATRA_ENFORCE_WEBHOOK_SIGNATURE (default off/log-only).
Needs-Render-proof: curl POST /bot with bad sig → 200 + log line; with PATRA_ENFORCE_WEBHOOK_SIGNATURE=true → 401.

## F10 — DONE (commit cafbc2798)
Bug (a): script/patra_reply_smoke.rb:165 labeled raw_field reasoning-first while the REAL parser is content-first (reply_service.rb:2114-2116, commit f66255eb2) → live run showed raw_field=reasoning_content while reply length == content_len.
Fix: label mirrors parser (content first, reasoning only when content blank).
Proof (b): tmp/self_tests/f10_raw_field_label_test.rb → REPRO OK (both-fields shape mislabeled pre-fix), FIX OK x4. ALL PASS.

## F14 — DONE (commit 6b47adfb1)
Bug (a): send_api_service.rb:157-160 — Graph failures only logged + false; FB error 190 (dead page token) = ALL sends silently dropping.
Fix: token_error? detects error.code==190 in parsed body; alert_token_failure → loud log + Games::TelegramNotifier.api_error, throttled once/hour/page via Redis setex (patra:fb_token_alert:<inbox>, TTL 3600 — telegram_notifier.rb:366-376 pattern). Fully rescued (alerting can't break sends). Full auto-refresh NOT implemented → report-only item for the report.
Proof (b): tmp/self_tests/f14_fb_token_alert_test.rb → DETECT OK, THROTTLE OK x2, TTL OK. ALL PASS.

## F17 — DONE (commit 61f947f1b)
Bug (a): pending_payment_timeout_job.rb:8-25 log-only, never inspects GameAction pending rows — stuck money actions invisible.
Fix: alert_stuck_game_actions — GameAction status=pending created_at<1h ago (limit 50, .to_a), loud warn log always; telegram api_error per account (ids+amounts+age), throttled 1/hr via setex patra:stuck_pending_alert TTL 3600. Zero state mutation; conversation loop untouched; fully rescued.
Proof (b): tmp/self_tests/f17_stuck_pending_test.rb → ALERT OK (ids+amounts), THROTTLE OK, NONE OK, MUTATION OK. ALL PASS.

## F20 — DONE (commit b7476b86b)
Bug (a): reply_job.rb had no retry_on; ApplicationJob only discards DeserializationError; sidekiq.rb sets no cap → unhandled error = Sidekiq default 25 retries ≈ 25 DeepSeek hits per poisoned message.
Fix: retry_on StandardError attempts:3 + retry_on Messaging::TransientSendError attempts:5 (last-defined wins for the subclass), polynomial backoff, loud GIVING UP log instead of raise on exhaust.
Proof (b): tmp/self_tests/f20_reply_job_retry_test.rb → REPRO OK (bubbles pre-fix), FIX OK x3 (3-call cap / 5 transient / recovery stops). ALL PASS.
Needs-Render-proof: enqueue a ReplyJob for a bogus conversation id, watch it stop after 3 attempts.

## F11 — DONE (commit 37fafc442) [HOT chatwoot_bridge_service via tmp/self_tests/f11_patch_bridge_service.py]
Bug (a): resolved_inbox_id (:388 pre-fix) fell back to ENV CHATWOOT_BRIDGE_INBOX_ID with NO existence check; ENV points at deleted inbox 5 (real Channel::Api = 28/29) → conversation create 404 → BridgeError → inbound FB messages dropped when page-match fails.
Fix: fallback chain = page-matched inbox → ENV id only if Inbox.exists?(id:, channel_type:'Channel::Api') → first Channel::Api on bridge account + WARN → raw ENV passthrough (orig behavior). Rescued (DB hiccup = old behavior). Readiness check now lists available Channel::Api inboxes on FAIL. CRLF preserved, region re-read, ruby -c OK.
Proof (b): tmp/self_tests/f11_bridge_inbox_fallback_test.rb → REPRO OK + FIX OK x5 incl. live-shaped fixture (5 deleted, 2 FacebookPage-broken, 28/29 real). ALL PASS.
Needs-Render-proof: bundle exec rails runner "svc=Facebook::ChatwootBridgeService.allocate; svc.instance_variable_set(:@page_id,'nope'); puts svc.send(:resolved_inbox_id)" (expect 28/29 + WARN, not 5).

## F8 — DONE (commit 41181bf35)
script/patra_deactivate_clientless_games.rb: plan-first, --confirm gated, idempotent (only active→deprecated, rerun empty), warns when a clientless game has agent_games. Uses Games::ClientRegistry.supported_slugs (read-verified client_registry.rb:16-36).
Proof (b): tmp/self_tests/f8_deactivate_clientless_test.rb → PLAN/EXEC/IDEMPOTENT OK vs real registry slugs. ALL PASS.
Needs-Render-proof: bundle exec rails runner script/patra_deactivate_clientless_games.rb (plan), then --confirm.

## F9 — DONE (commit c617d433f) [HOT reply_service via tmp/self_tests/f9_patch_reply_service.py]
Bug (a): fetch_payment_info WARNed every reply for account 2 (reply_service.rb:1844-1847) — no canned response 'payment_info' and no fallback; prompt got '' → model escalates payment questions. No seeding pattern exists in repo (db/seeds.rb is demo-only) → silence-with-correct-fallback chosen.
Fix: payment_info_from_handles — live active PaymentHandles (first priority per platform, cooldown-aware, display_handle + person name), cached under same canned key TTL 600 so a real canned response takes over ≤10min. WARN only when canned missing AND no handles. 2 patcher edits, 1 match each, CRLF kept, region re-read.
Proof (b): tmp/self_tests/f9_payment_info_fallback_test.rb → FALLBACK OK (CASHAPP: $sofiamann8 (Sofia Mann) / VENMO: @venmogal), EMPTY OK. ALL PASS.
Needs-Render-proof: rails runner "svc=Ai::ReplyService.new(<conv>, account_id: 2); puts svc.send(:fetch_payment_info)"

## F7 — DONE (commit 963cd5a4e)
Bug (a): action_executor.rb:310-320 treated documented already-exists codes like any failure (status failed + record_failure! + escalation). Codes read-verified: GameVault family 20 'Account name already exists' (game_vault/client.rb STATUS_CODES), FastApi family 12 'User Already Exist' (fast_api/client.rb STATUS_CODES; FastApi 20 = Password error — families must not share the constant).
Fix: already_exists_code? on GameVault::Client (20; vegas_sweeps inherits) + FastApi::Client (12; vblink/ultra_panda inherit). ActionExecutor#add_player: documented code + get_user_id verification → action flipped to success ('existing account verified, reused'), reset_failures!, returns ok:true + reused_existing:true. No method on Juwa/Laravel/AspNet → unchanged. Verification failure → unchanged escalation.
CAVEAT for report: orchestrator derives password per (username, slug) — on reuse the messaged password may be wrong for the sibling-skin account. Proposed follow-up (report-only, NOT applied): on reused_existing, orchestrator should call reset_player_password or omit the password line.
Proof (b): tmp/self_tests/f7_already_exists_reuse_test.rb → 6 checks ALL PASS incl. FastApi-20-is-password-error guard.

## SELF-AUDIT #1 (R7, after 13 fixes)
ruby -c on all 20 touched .rb → 0 failures · schedule.yml YAML OK · git log 495a02cae..HEAD = 13 per-fix commits + init, ZERO frontend files · working tree clean except this run log + other session's PATRA_RUN_LOG.md (untracked, not mine).

## F18 — DONE as probe + report-only diagnosis (commit 29f14bef2)
Diagnosis (a, read-verified):
- Juwa: agent_balance (juwa/client.rb:142-149) returns ok:true with agent_balance=resp.dig('data','agent_balance') — ANY key drift in the provider JSON gives "connect OK, balance nil" silently. No fallback keys, no warn.
- PandaMaster (asp_net_panel/base_client.rb:61-65, 200-204): balance scraped from HTML via /updateBalance\("Balance:([\d.]+)"\)/ — regex does NOT match thousands separators (e.g. "Balance:1,234.56") or any markup drift; test_connection still reports Connected (session valid) → exact "connect OK, balance empty" symptom.
Cannot pick which without live bytes (zero-guessing) → script/patra_balance_probe.rb (READ-ONLY) prints raw Juwa agentBalance body+keys and the exact updateBalance HTML snippet vs the current regex.
Needs-Render-proof: bundle exec rails runner script/patra_balance_probe.rb → paste output; fix becomes a one-liner (key fallback or regex [\d,.] + tr(',','')) once evidence shows which.

## F19 — REPORT-ONLY (no commit; evidence (a) read-verified)
Mechanism EXISTS and IS WIRED on the production path: WinbackService flags messages additional_attributes.winback=true (winback_service.rb:103-110) → SendApiService#winback_tag_opts (send_api_service.rb:91-106) attaches messaging_type=MESSAGE_TAG + message_tag=HUMAN_AGENT → OutboundDispatcher threads opts (:28-29) → ZernioProvider body messagingType/messageTag (zernio_provider.rb:24-27). WinbackService correctly telegram-falls-back for >7d (FB_TAG_MAX_DAYS=7).
The live "#10 outside allowed window" failures cannot be tag-fixed:
1. Contacts::ReEngageJob (re_engage_job.rb:22-26) targets last_activity_at < 7d+ ago and sends PLAIN MessageBuilder messages (no winback flag) → untagged → #10 guaranteed >24h. NO tag is valid >7d.
2. Reengagement::DormantPlayerJob/SendService targets stale >7d conversations (dormant_player_job.rb:41-51) — same.
3. Minor gap: SendApiService direct-Graph path deliver_to_facebook (:140-149) never attaches the tag even for flagged winback messages — only matters if an inbox uses messaging_provider 'direct_meta' (production uses zernio). Graph param name (`tag`) is not in-repo → would be invention; report-only.
PRECISE PROPOSED CHANGE (not applied): in Reengagement::SendService#call and ReEngageJob#send_reengage, branch on last incoming age: <=7d → create message with additional_attributes {'winback'=>true} (rides the existing HUMAN_AGENT pipe); >7d → Games::TelegramNotifier.winback_manual_alert + private note (WinbackService deliver_via_telegram pattern, :119-136). Policy risk to state in report: HUMAN_AGENT tag on automated re-engagement is gray-zone (FB intends it for human agents within 7d); volume tagging may risk page quality score.

## F5 — DONE (commit 45d99a65c) [HOT reply_service via tmp/self_tests/f5_patch_reply_service.py]
Bug (a): build_messages hardcoded @latest_timestamp = Time.current.to_i (pre-fix :1311) while call's gate (:337-341, 10-min MESSAGE_FRESHNESS_WINDOW) read it → gate permanently no-op, stale conversations always replied to.
Fix: @latest_timestamp = max incoming-message created_at via the file's own chat_message_type/message_created_at_unix; empty/outgoing-only → 0 → below FRESHNESS_UNIX_MIN → gate passes → unchanged no-usable-history path.
Proof (b): tmp/self_tests/f5_freshness_gate_test.rb → REPRO OK + FIX OK x6 (stale/fresh/empty/outgoing-only/ISO8601/10-min boundary). ALL PASS.

## F16 — DONE (commit 8307296ec) [HOT reply_service via tmp/self_tests/f16_patch_reply_service.py, separate commit from F5]
Feature: outgoing non-private message with source_id != 'ai_auto' (the marker ReplyJob stamps, reply_job.rb AI_SOURCE_ID) = human takeover → AI paused for PATRA_TAKEOVER_PAUSE_MINUTES (call-time read, default 0 = OFF = behavior unchanged). New gate sits AFTER ai_disabled? (ai-off label untouched). 3 patcher edits, 1 match each.
Proof (b): tmp/self_tests/f16_takeover_pause_test.rb → CAPTURE OK (ai_auto + private ignored), DEFAULT OK, GATE OK x3. ALL PASS.
ENV knob: PATRA_TAKEOVER_PAUSE_MINUTES (default 0=off).

## F12 — DONE (commit 741d5a44e) [HOT orchestrator via tmp/self_tests/f12_patch_orchestrator.py, 5 edits]
Bug (a): payment_already_loaded? (:1737-1750 pre-fix) is check-then-act; order_id random (game_action.rb:27-29) → N concurrent messages for ONE payment all load. UNIQUE INDEX (account_id, order_id) PROVEN pre-existing (db/migrate/20260513030000_create_game_actions.rb:29 — schema.rb is stale at version 2026_05_07 and lacks the table entirely) → migration skipped per spec.
Fix: deterministic_payment_order_id(payment_id) = "pay"+SHA1(account:contact:payment_id)[0,20]; success/pending existing → nil → already_loaded_response (skip + correct reply); failed attempts free the base via _a<count> suffix (code-8 auto-create retry still works). All 4 automated load sites (handle_load_intent initial+retry :415/:464, handle_username_provided initial+retry :1031/:1076) pass the id and rescue IdempotencyError/RecordNotUnique as already-loaded. Manual/freeplay/bonus loads keep their random scheme.
Proof (b): tmp/self_tests/f12_order_id_race_test.rb → REPRO OK (3x pre-fix loads), FIX OK x5 + INVARIANTS OK. Harness gains [F12] section driving the REAL helper + REAL unique index.
Needs-Render-proof: bundle exec rails runner script/patra_money_harness.rb (F12 cases green).

## F13 — DONE, VERIFIED-NO-CHANGE (commit a428a2a96)
Verified (a): cap enforced at action_executor.rb:71-72 → amount_limit_error('max_load_amount') (:252-258, credentials JSONB) BEFORE GameAction create/panel call; orchestrator automated path loads ONLY via executor.load_player (read-verified both handlers). No bypass exists. Over-cap on automated path → ok:false → orchestrator failure branch → human_escalation telegram + needs-human label (read-verified :522-536).
Harness: [F13] section drives REAL handle_load_intent with capped (10) and uncapped credentials (save/restored): over-cap = no recharge + needs-human + telegram; unset = unlimited kept.

## F15 — DONE (commit a4eca89a6)
Feature (dark): ApprovalRequest after_update_commit (status→approved) → Approvals::AutoResumeJob → Approvals::AutoResume.execute! — ONLY when PATRA_APPROVAL_AUTORESUME=true (default off: callback no-ops, manual behavior byte-identical). Execution: order_id "appr_<id>" on the unique index = exactly-once (double-approve/job-retry/race all no-op); executor cashout_player gains skip_approval_gate kwarg (only AutoResume passes true — prevents infinite re-gate); reject never executes; invalid payload → telegram + manual; failure → cashout-group telegram with REAL action status + NEEDS HUMAN. Files: app/services/approvals/auto_resume.rb (new), app/jobs/approvals/auto_resume_job.rb (new, 3-attempt bounded retry), app/models/approval_request.rb (additive callback), action_executor.rb (kwarg), harness 8 cases.
Proof (b): tmp/self_tests/f15_approval_autoresume_test.rb → 7 checks ALL PASS (dark/once/double/reject/failure/invalid/race).
ENV knob: PATRA_APPROVAL_AUTORESUME (default off).
Needs-Render-proof: harness F15 section green; then with flag on, approve a real test request.

═══ PHASE 1 COMPLETE — all F1-F20 done (18 commits) ═══

(append below as work completes)
