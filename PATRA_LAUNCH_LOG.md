# PATRA LAUNCH NIGHT v3 — TAB B LOG (backend hardening, money-path specs, live-AI endpoints)

## MORNING SUMMARY (run complete — 22 commits, all prefixed `patra-launch:`)
**Everything in the queue shipped.** Zero hot-file/RAG/frontend/views/migrate edits (lane proof in FINAL below). No pushes, no deploys, no real side effects — all external calls in specs/scripts mocked.

**Security (act on these first):**
- 🔴 ROTATION MANDATORY: telegram bot token + juwa secret key are in public git history (verified). See SECRETS_ROTATION_RUNBOOK.md. Juwa hardcoded fallback removed from code; BACKUP folder untracked+gitignored.
- 🔴 Telegram webhook had ZERO validation → HMAC secret validation shipped (opt-in: re-save telegram channels, then set TELEGRAM_WEBHOOK_VALIDATE_SECRET=true).
- 🟠 incident endpoints (broadcast to all open convos / mass reassign / pause AI) were open to ANY agent → admin-gated. backup_pages leaked FB access_tokens in JSON → redacted + admin-gated. Full TEN table below.

**Real bugs found & fixed (would have fired in prod):**
- HandleHealthMonitor alert called a PRIVATE TelegramNotifier method positionally → NoMethodError on every flagged payment handle; also re-alerted every sweep. Fixed (api_error + skip-disabled).
- Ai::CopilotService called OpenAI with a key Patra doesn't have → copilot/smart-compose/suggest-tags endpoints silently returned '' in prod. Rerouted to DeepseekClient.
- Patra dashboard computed money stats 3× (12 queries → 4).

**Shipped:** money-path spec suite (transfer forks/dedup/velocity/idempotency, action_executor audit, fastapi+asp.net panel clients, winback, deepseek retry, ai fleet, payment-job idempotency, model validations, tenancy gates — 15 new spec files, factories included). Live-AI endpoints HB-1 (conversation analysis) + HB-2 (persona playground) + routes + api_docs. DeepseekClient 5xx/timeout retry. Telegram update dedup. Typed FB GraphApiError. Sentry message-body scrub. [MONEY] structured logging. Rack-attack throttles. Data-integrity script. Readiness §5b. PATRA_BACKEND_MAP.md + LAUNCH_RUNBOOK.md + SECRETS_ROTATION_RUNBOOK.md.

**Caveat:** ALL new specs are SPECS-UNRUN locally (ruby 3.4.9 vs Gemfile 3.4.4 — bundler refuses; every file ruby -c clean). Run list + exact commands in SPECS-UNRUN below. Rubocop also blocked (same cause) — command in LINT note.

## ROLLBACK HASH
`5bfb2862a396b21f95361d1dd9dcc01637ec04a4` (main @ run start, clean tree)

## SHARED RULES (S1-S8) — VERBATIM, re-read after every compaction
S1 LANES — you may EDIT ONLY: non-hot .rb services/jobs/models, spec/** (new files), api/v1/accounts/patra/*
   + backup_pages + cashier_claims + referrals + webhooks controllers + super_admin/*.rb controllers,
   config/initializers, Gemfile, docs/**, script/** (additive), .gitignore, .env.example, routes.rb (your
   new endpoints only). FORBIDDEN (sibling lanes): the 4 hot files (READ/CALL only): reply_service.rb,
   conversation_orchestrator.rb, intent_detector.rb, chatwoot_bridge_service.rb; ALL intent/RAG/bella files
   (app/services/bella_rag/**, *intent*/*rag*/*bella*) — TAB A owns; app/javascript/** + .vue + public/vite
   — TAB A owns; app/views/** + app/dashboards/** + db/migrate/** + features.yml — TAB C owns. Need =
   DEFERRED-RAG / HANDOFF-A / HANDOFF-C in the log.
S2 GIT — git add <explicit paths> && git commit --no-verify -m "patra-launch: <id> <summary>". NEVER -A /
   commit -a / add . — siblings have staged files.
S3 NEVER push/pull/rebase/stash/reset --hard (destroys sibling commits). Undo own commit = git revert
   <hash> --no-edit. index.lock = wait 30s retry x10.
S4 Red spec? git log --oneline -5 + git status first. Sibling committed recently → wait 3 min, re-run. If a
   sibling's committed behavior change broke your spec, UPDATE THE SPEC to the new behavior, never revert
   their commit.
S5 NEVER stage/edit sibling logs or owner-WIP files even if modified/untracked: telegram_notifier.rb,
   winback_service.rb, base_provider.rb, outbound_dispatcher.rb, zernio_provider.rb, PATRA_RUN_LOG.md,
   PATRA_OVERNIGHT_RUN_LOG.md, PATRA_FEAT_LOG.md. Service exists only as uncommitted WIP → DEFERRED-WIP.
S6 Local test env may not boot — NOT a failure: ruby -c + write the spec + SPECS-UNRUN with exact setup
   steps. Never fake a pass, never skip writing the spec.
S7 Never ask/idle. Safest branch + log under DECISIONS.
S8 routes.rb is SHARED with TAB C: re-read immediately before every edit; add your routes as a minimal
   insertion; failed replace → re-read + re-apply.

## QUEUE
- [x] SEC-1 git rm -r --cached patra-automation-BACKUP/ + .gitignore (commit df05b758e)
- [x] SEC-2 repo-wide hardcoded-creds grep → ENV.fetch (commit 4e696eeb3: Juwa secret removed from initializer + client; vars.json files untracked+already gitignored; no other live values in tracked code)
- [x] SEC-3 .env.example names + SECRETS_ROTATION_RUNBOOK.md (commit a46c61a05; CONFIRMED in git history: telegram bot token in BACKUP README @0d4c177, juwa secret in code — rotation mandatory)
- [x] TEN tenancy/auth audit all custom controllers + fixes + findings table (commits f52a82544, 8766135b8, eb98c75a4 — see FINDINGS TABLES)
- [x] SPEC-a four money handlers specs (4c5c1f476 — transfer forks, over-amount, dedup, per-load counting, reissue, replay read-only)
- [x] SPEC-b fraud guards specs (4c5c1f476 — velocity, duplicate-payment, fail-open dedup, record_api_failure!/success! degrade+reset)
- [x] SPEC-c Ai::DeepseekClient (3ad3e75a7 — ADDED single retry on 5xx/timeout, 4xx never retried; spec covers reasoning_content fallback, nil-key short-circuit)
- [x] SPEC-d win-back specs (ad1304747 — winback_service IS in git HEAD so specced per mandate; only new spec file created)
- [x] GAME game-plumbing specs (3d8d62404 action_executor + fastapi family; 2b7964d2b asp_net_panel base client)
- [x] AIX AI service fleet hardening + specs (3354030f4 fixes + 6210f0e4c specs; copilot_service moved off dead OpenAI path to DeepseekClient)
- [x] FBSRV facebook pipeline hardening + specs (089be15c8 — typed GraphApiError w/ fb_code; send_api_service already had 190 handling+throttle, graph_profile fails soft — verified by audit, no edits needed there)
- [x] PAYJOBS payment jobs audit + idempotency specs (3354030f4 + 6210f0e4c; found REAL BUG: handle monitor alert called private TelegramNotifier.notify positionally → NoMethodError on every flag — fixed to api_error)
- [x] HB-1 PatraAiAnalysisController#create endpoint (cc2d8fcbf)
- [x] HB-2 PatraPlaygroundController#create endpoint (cc2d8fcbf)
- [x] MODEL validations audit + specs (3fef47089 — amount numericality on game_action/cashier_claim/referral, self-referral fraud guard, transfer-mode enum integrity; spec for all 10 models)
- [x] PERF N+1 audit (415cac356 — dashboard load_cashout_stats 3 calls→1: 12 queries→4; game_health already includes(:game); conversations single-record = clean)
- [x] IDX index audit (415cac356 — db/schema.rb is STALE/pre-Patra, audited db/migrate directly; 1 gap → docs/proposed_migrations/20260610_add_game_actions_money_guard_index.rb; full table in docs/proposed_migrations/README.md; NOTHING in db/migrate, nothing run)
- [x] RATE rack_attack throttles (415cac356 — telegram webhook 120/min/IP, live-AI 30/min/IP, claim mutations 30/min/IP; env-tunable)
- [x] OBS (7e2802058 — sentry env-gating was OK, added recursive key-scrub for message bodies/passwords/tokens; [MONEY] log line per audited action in action_executor; BetterStack /health documented in LAUNCH_RUNBOOK)
- [x] DATA script/patra_data_integrity.rb (933aea696 — read-only; NOT run locally, see SPECS-UNRUN; run on Render Shell: `bundle exec rails runner script/patra_data_integrity.rb`)
- [x] DEP report-only (in LAUNCH_RUNBOOK — npm: 9 vulns, 1 high = glob CLI build-time-only vector, NO package changes (TAB A's toolchain); gems: all current patch lines, bundler-audit blocked locally → Render command documented; no Gemfile change, apply-condition unverifiable)
- [x] LINT — BLOCKED locally (bundler refuses: ruby 3.4.9 vs 3.4.4). All files ruby -c clean. Run after env fix: `bundle exec rubocop -a <files in FINAL list>`
- [x] DOCS (c3ba0e13b — docs/PATRA_BACKEND_MAP.md full architecture + api_docs generator entries for both new endpoints)
- [x] READY (8fea53a26 — readiness §5b purely appended: env completeness, HB endpoint route smoke, telegram secret posture, no-tracked-secrets; LAUNCH_RUNBOOK.md complete)
- [x] FINAL lane proof + sweep (below)

## FINAL — LANE PROOF (vs rollback 5bfb2862a)
22 `patra-launch:` commits. Files touched by MY commits only (verified via git diff-tree per commit, combined sibling diff excluded):
- ZERO hot files (reply_service/conversation_orchestrator/intent_detector/chatwoot_bridge_service untouched by my commits — orchestrator appears in the combined branch diff from a SIBLING commit)
- ZERO intent/RAG/bella files; ZERO app/javascript/.vue/public/vite; ZERO app/views/app/dashboards/db/migrate/features.yml
- ZERO owner-WIP files staged (telegram_notifier, winback_service, base_provider, outbound_dispatcher, zernio_provider, sibling logs — read-only only)
- patra-automation-BACKUP entries = SEC-1 mandated UNTRACKING (deletions from index; files remain on disk)
- ruby -c sweep over every .rb my commits touched: ALL Syntax OK

## SPECS-UNRUN (all new spec files — exact commands)
CAUSE: local ruby 3.4.9 vs Gemfile-pinned 3.4.4 → bundler refuses all bundle exec (rspec, rubocop, rails runner). Every file syntax-checked with ruby -c.
SETUP: install ruby 3.4.4 (rbenv/RubyInstaller) → `bundle install` → test DB (`RAILS_ENV=test bundle exec rails db:create db:schema:load` — NOTE schema.rb stale; use db:migrate) → run below. OR run on Render Shell directly.
```
bundle exec rspec \
  spec/controllers/webhooks/telegram_secret_validation_spec.rb \
  spec/controllers/api/v1/accounts/patra/tenancy_hardening_spec.rb \
  spec/controllers/api/v1/accounts/patra_live_ai_endpoints_spec.rb \
  spec/services/games/money_handlers_spec.rb \
  spec/services/games/action_executor_spec.rb \
  spec/services/games/fast_api_client_spec.rb \
  spec/services/games/asp_net_panel_base_client_spec.rb \
  spec/services/games/winback_service_spec.rb \
  spec/services/ai/deepseek_client_spec.rb \
  spec/services/ai/ai_fleet_spec.rb \
  spec/services/facebook/patra_graph_service_spec.rb \
  spec/jobs/patra_payment_jobs_spec.rb \
  spec/models/patra_models_spec.rb
```
Also unrun: `bundle exec rails runner script/patra_data_integrity.rb` (read-only) and `ruby script/patra_launch_readiness.rb` (needs prod env).
Per S4: if a spec is red against a fresh TAB-A commit to the game clients, update the SPEC to the new behavior.

## DECISIONS
- D0 (run start): tree clean at 5bfb2862a, no existing launch log → fresh start from SEC-1.
- D1 (SEC-2): juwa2/vegas_sweeps hardcoded AGENT-ID defaults ('1009','153472') left in place — identifiers not secrets, removal risks prod breakage with no security gain. Documented in rotation runbook.
- D2 (TEN): cashier_claims claim/complete NOT admin-gated — it's the agent work queue; gating would break the cashier workflow. Scoping verified.
- D3 (TEN): telegram webhook secret enforcement is OPT-IN (warn-only default) because existing webhooks were registered without a secret; flipping TELEGRAM_WEBHOOK_VALIDATE_SECRET=true before re-registering would drop all telegram traffic.
- D4 (TEN): super_admin minor findings (read-only raw SQL, missing transaction, unmounted games controller) → HANDOFF-C; TAB C actively owns admin console tonight, all items behind super-admin auth.
- D5 (AIX): Ai::CopilotService rerouted from OpenAI (OPENAI_API_KEY not in Patra stack → copilot/smart_compose/suggest_tags silently returned '' in prod) to shared Ai::DeepseekClient. Same contract: String, never raises.
- D6 (PAYJOBS): RotatePlayerMemoryJob flagged "broken idempotency" by audit subagent — VERIFIED FALSE by reading: current_summarized re-reads persisted contact state, fold_plan re-checks the 1000 trigger, so a retry no-ops or advances correctly. No change made.
- D7 (HB-2): ReplyService#build_system_prompt is an instance method woven into hot-path state (@bridge_account_id, SYSTEM_PROMPT, dynamic_game_rules_prompt) — NOT cleanly callable without hot-file coupling. Built Ai::PlaygroundPromptBuilder replicating persona rules instead, per mandate fallback.
- D8 (FBSRV): imap_check_job in-job sleep(30) on IMAP rate limit left as-is — changing retry semantics on the money-adjacent IMAP poller overnight is riskier than the antipattern; lock key already prevents overlap. Logged as accepted finding.

(SPECS-UNRUN: full consolidated list with exact commands is in the dedicated section after FINAL.)

## DEFERRED-HOT / DEFERRED-WIP / DEFERRED-RAG / HANDOFF-A / HANDOFF-C
- HANDOFF-C: super_admin minor code-quality findings (raw read-only SQL in patra_dashboard#db_size, no transaction in app_configs#create loop, push_diagnostics destroy_all→delete_all, UNMOUNTED super_admin/games_controller.rb dead code, platform_banners controller has routes but no actions). All behind super-admin auth — nothing exploitable. TAB C owns admin console.
- HANDOFF-A (FYI, no action needed from me): npm audit found 1 high (glob 10.2–10.5, build-CLI vector) + 7 moderate — package/lock changes are TAB A's toolchain; report in LAUNCH_RUNBOOK DEP section.
- DEFERRED (operator): regenerate stale db/schema.rb (`bundle exec rails db:schema:dump` against a migrated DB) — it predates every Patra table.
- No DEFERRED-HOT (no secret/cred usages found inside hot files), no DEFERRED-WIP (winback IS in HEAD → specced), no DEFERRED-RAG.

## FINDINGS TABLES

### TEN — tenancy/auth audit (3 parallel read-only subagents, fixes sequential)
| Finding | Severity | Status |
|---|---|---|
| webhooks/telegram: NO secret validation — anyone with a bot token could forge inbound events | CRITICAL | FIXED f52a82544 — HMAC-derived secret registered via setWebhook, header validated; enforcement opt-in via TELEGRAM_WEBHOOK_VALIDATE_SECRET (re-save telegram channels first) |
| patra/incident: pause_ai / broadcast_open / reassign_all open to ANY agent | HIGH | FIXED 8766135b8 — admin-gated + blank-message guard |
| backup_pages: access_token serialized in every JSON response; mutations open to agents | HIGH/MED | FIXED 8766135b8 — as_json strips access_token; create/update/destroy/reorder admin-only |
| patra/ai: 4 conversation actions skipped Pundit (agent without inbox access could use them) | MED | FIXED 8766135b8 — set_conversation + authorize :show? (mirrors conversation_summary) |
| referrals#update_settings: any agent could change account-wide bonus amounts | MED | FIXED 8766135b8 — update_settings admin-only; create/update left agent-accessible (agents log referrals mid-chat) |
| patra/holidays: inbox_id not validated to account (cross-account ref possible) | MED | FIXED 8766135b8 — ownership check, 422 on foreign inbox |
| cashier_claims claim!/complete!: no role gate | (flagged HIGH by audit) | NO CHANGE — DECISION D2: claims ARE the cashier work queue; agents must claim/complete. Tenancy scoping verified OK. |
| ai#analyze_image: signed blob id not account-checked | LOW | NO CHANGE — signed IDs are app-issued/tamper-proof; cross-account needs a leaked signed URL |
| super_admin/*: all gated via authenticate_super_admin! + devise scope; games_controller exists but UNMOUNTED (dead code); minor: raw read-only SQL in patra_dashboard db_size, no transaction in app_configs loop | LOW | HANDOFF-C — TAB C owns admin console tonight; nothing exploitable (all behind super-admin auth, games controller unreachable) |
| All 15 patra/* + 3 account controllers: tenancy scoping (Current.account.*) verified clean by audit | OK | — |
