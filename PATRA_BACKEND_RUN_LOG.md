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
- [ ] F1 Re-engagement shared cooldown (3 senders, ENV PATRA_REENGAGE_COOLDOWN_HOURS=24, stagger schedule.yml) — todo
- [ ] F2 shift_report_job.rb:33 TelegramNotifier positional-call crash — todo
- [ ] F3 expire_claims_job.rb:19 same crash every minute; rescue around notify — todo
- [ ] F4 bot_controller X-Hub-Signature-256 HMAC, log-only default, enforce via ENV — todo
- [ ] F5 [HOT reply_service] dead freshness gate @latest_timestamp hardcoded ~:1311 — todo
- [ ] F6 conversation_summary_service Array-treated-as-Message crash (conv 111) — todo
- [ ] F7 shared-namespace add_player already-exists = success-reuse — todo
- [ ] F8 script/patra_deactivate_clientless_games.rb (--confirm gated) — todo
- [ ] F9 payment_info canned-response WARN account 2 — todo
- [ ] F10 patra_reply_smoke.rb stale raw_field label — todo
- [ ] F11 bridge inbox fallback CHATWOOT_BRIDGE_INBOX_ID → first Channel::Api — todo
- [ ] F12 [HOT orchestrator + migration] deterministic order_id + UNIQUE index + rescue-as-already-loaded — todo
- [ ] F13 per-agent max_load_amount enforced on automated path — todo
- [ ] F14 FB error 190 loud log + throttled telegram alert (1/hr/page) — todo
- [ ] F15 approval-gate auto-resume dark behind PATRA_APPROVAL_AUTORESUME — todo
- [ ] F16 [HOT reply_service, separate commit] human-takeover auto-pause PATRA_TAKEOVER_PAUSE_MINUTES=0 — todo
- [ ] F17 stuck-pending sweeper throttled telegram alert >1h — todo
- [ ] F18 Juwa + Panda Master blank balance diagnosis — todo
- [ ] F19 win-back FB policy MESSAGE_TAG (only if mechanism exists) — todo
- [ ] F20 ReplyJob bounded retries / poison-message giveup — todo

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
(append below as work completes)
