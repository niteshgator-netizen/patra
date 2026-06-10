# PATRA LAUNCH NIGHT v3 — TAB B LOG (backend hardening, money-path specs, live-AI endpoints)

## MORNING SUMMARY
(to be filled at end of run)

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
- [ ] SPEC-a four money handlers specs
- [ ] SPEC-b fraud guards specs (velocity, duplicate-payment, record_api_failure!/success!)
- [ ] SPEC-c Ai::DeepseekClient fallback + retry specs
- [ ] SPEC-d win-back specs (only if in git HEAD)
- [ ] GAME game-plumbing specs (action_executor, base_client, provider clients)
- [ ] AIX AI service fleet hardening + specs
- [ ] FBSRV facebook pipeline hardening + specs
- [ ] PAYJOBS payment jobs audit + idempotency specs
- [ ] HB-1 PatraAiAnalysisController#create endpoint
- [ ] HB-2 PatraPlaygroundController#create endpoint
- [ ] MODEL model validations audit + specs
- [ ] PERF N+1 audit patra dashboard/conversations/game_health
- [ ] IDX index audit → docs/proposed_migrations/
- [ ] RATE rack_attack throttles
- [ ] OBS sentry audit + structured logging + BetterStack note
- [ ] DATA script/patra_data_integrity.rb
- [ ] DEP npm report-only + Gemfile advisory report
- [ ] LINT rubocop -a on own files only
- [ ] DOCS PATRA_BACKEND_MAP.md + api_docs refresh
- [ ] READY readiness script additive checks + LAUNCH_RUNBOOK.md
- [ ] FINAL diff-vs-rollback lane proof + log completion

## DECISIONS
- D0 (run start): tree clean at 5bfb2862a, no existing launch log → fresh start from SEC-1.
- D1 (SEC-2): juwa2/vegas_sweeps hardcoded AGENT-ID defaults ('1009','153472') left in place — identifiers not secrets, removal risks prod breakage with no security gain. Documented in rotation runbook.
- D2 (TEN): cashier_claims claim/complete NOT admin-gated — it's the agent work queue; gating would break the cashier workflow. Scoping verified.
- D3 (TEN): telegram webhook secret enforcement is OPT-IN (warn-only default) because existing webhooks were registered without a secret; flipping TELEGRAM_WEBHOOK_VALIDATE_SECRET=true before re-registering would drop all telegram traffic.
- D4 (TEN): super_admin minor findings (read-only raw SQL, missing transaction, unmounted games controller) → HANDOFF-C; TAB C actively owns admin console tonight, all items behind super-admin auth.

## SPECS-UNRUN (exact local setup steps at bottom of this section)
- spec/controllers/webhooks/telegram_secret_validation_spec.rb
- spec/controllers/api/v1/accounts/patra/tenancy_hardening_spec.rb
- CAUSE: local ruby is 3.4.9 but Gemfile pins 3.4.4 → bundler refuses (`bundle check` fails), `bundle exec rspec` unavailable.
- SETUP TO RUN: install ruby 3.4.4 (e.g. `rbenv install 3.4.4` / RubyInstaller 3.4.4 on Windows), `gem install bundler`, `bundle install`, set DATABASE_URL to a local postgres with pgvector, `RAILS_ENV=test bundle exec rails db:create db:schema:load`, then `bundle exec rspec <files>`. On Render Shell: `bundle exec rspec <files>` directly.

## DEFERRED-HOT / DEFERRED-WIP / DEFERRED-RAG / HANDOFF-A / HANDOFF-C
(none yet)

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
