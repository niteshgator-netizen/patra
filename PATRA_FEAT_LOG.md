# PATRA_FEAT_LOG.md — TAB C: SUPER-ADMIN OPERATOR CONSOLE

## ☀️ MORNING SUMMARY (run complete — 2026-06-10)
ALL 7 ADM ITEMS SHIPPED in 8 commits (`git log --grep '^patra-feat:'`), rollback hash `5bfb2862a...`.
- ADM5 ✅ append-only audit trail: Patra::AdminAudit.record + credential scrubber + read-only
  Administrate dashboard at /super_admin/patra_admin_audit_logs (newest-first, filters).
- ADM1 ✅ Command Center at /super_admin/patra_dashboard: accounts/engagement/MONEY(by day+game+top
  accounts)/RISK/integrations/billing-defensive, 7/30/90d + custom range. New Patra::FinanceAnalytics.
- ADM2 ✅ /super_admin/patra_accounts/:id panel + audited suspend/reactivate/feature-toggle
  (reversible, reason-required, confirm dialog, NO delete, NO billing mutations).
- ADM3 ✅ /super_admin/patra_game_health matrix (accounts × games, down-first, per-game summary,
  error text only — credential-leak spec guard).
- ADM4 ✅ audited time-boxed (30min) impersonation with enter/exit/auto-expiry + red console banner;
  REPLACED the pre-existing UNAUDITED SSO impersonate link in users/_impersonate.erb. Full
  SECURITY-MODEL section below.
- ADM6 ✅ banner posting audited; pipeline verified end-to-end INCLUDING existing SPA StatusBanner.vue
  (no frontend gap). Note: requires DEPLOYMENT_ENV=cloud — check on Render if banners don't render.
- ADM7 ✅ suspension enforcement verified (401 via EnsureCurrentAccountHelper, next-request bite) +
  TWO real gaps CLOSED (public Patra widget POST, public help center) + webhook-pipeline gap
  documented as SG-1 with proposed fix (HANDOFF-B).
⚠ TO ACTIVATE MUTATIONS: set PATRA_ADMIN_CONSOLE_ACTIONS=true on Render (everything ships read-only/
  403 by default — HARD BOUND). Migration to run: 20260610090000 (additive create_table only).
⚠ SPECS WRITTEN BUT UNRUN (no local bundle — `bundler: command not found: rspec`, exit 127). 10 new
  spec files; see SPECS-UNRUN for the 3 setup commands. ruby -c: 28/28 files clean.
PROOFS (bottom of log): TAB-C commits touched ONLY lane files (zero hot/RAG/services/javascript/
  Gemfile/initializers/sibling-logs); routes diff = additions inside the marked EOF block only;
  credential self-grep CLEAN.

## ROLLBACK HASH
`5bfb2862a396b21f95361d1dd9dcc01637ec04a4` (main @ run start, clean tree)

## SHARED RULES (S1-S8) — VERBATIM, re-read after every compaction
S1 LANES — you may EDIT ONLY: app/views/**, app/dashboards/**, app/controllers/super_admin/** (your new
   patra_* controllers), scss/super_admin/index.scss, db/migrate (ADDITIVE create_table ONLY — never alter
   existing tables), features.yml, routes.rb (marked end-of-file block only), app/models (ONLY new models
   you create, e.g. PatraAdminAuditLog), lib/patra/** (your new modules), spec/** (your new spec files),
   app/controllers/concerns (your new impersonation concern). FORBIDDEN: the 4 hot files, all
   intent/RAG/bella files, app/services/** edits (READ/CALL only — TAB A/B own services), app/javascript/**
   + .vue + public/vite (server-rendered admin ≠ the SPA; SPA stays untouched), Gemfile,
   config/initializers (TAB B owns). Need = HANDOFF-A / HANDOFF-B in the log.
S2 GIT — git add <explicit paths> && git commit --no-verify -m "patra-feat: <id> <summary>". NEVER -A /
   commit -a / add . — siblings have staged files.
S3 NEVER push/pull/rebase/stash/reset --hard (destroys sibling commits). Undo own = git revert <hash>
   --no-edit. index.lock = wait 30s retry x10.
S4 Red spec? git log --oneline -5 + git status first; sibling committed recently → wait 3 min, re-run once.
S5 NEVER stage/edit sibling logs (PATRA_OVERNIGHT_RUN_LOG.md, PATRA_LAUNCH_LOG.md, PATRA_RUN_LOG.md) or
   owner-WIP files: telegram_notifier.rb, winback_service.rb, base_provider.rb, outbound_dispatcher.rb,
   zernio_provider.rb.
S6 Local env may not boot/migrate — NOT a failure: ruby -c + write specs + SPECS-UNRUN with exact setup
   steps. Never fake a pass.
S7 Never ask/idle. Safest option + log under DECISIONS.
S8 routes.rb SHARED with TAB B: re-read immediately before every edit; your routes go ONLY in the marked
   end-of-file block; failed replace → re-read + re-apply minimal.

## QUEUE
- [x] ADM5 — immutable admin audit trail (FIRST — ADM2/ADM4 depend on it)
- [x] ADM1 — platform command center
- [x] ADM2 — account lifecycle & control
- [x] ADM3 — integration health matrix
- [x] ADM4 — impersonation / support-login
- [x] ADM6 — platform banner
- [x] ADM7 — suspension safety-net
- [x] FINAL — proofs + morning summary

## DECISIONS
- D1: No marked TAB-C block existed in routes.rb → I will create one at end-of-file (inside the final
  `end`? NO — as a separate `devise_scope`-free block just before the file's final `end`), clearly marked
  `# == PATRA TAB-C ROUTES (super admin console) — DO NOT EDIT OUTSIDE TAB C ==`. Auth is enforced at
  controller level (`authenticate_super_admin!` in SuperAdmin::ApplicationController), so routes do not
  need to live inside the existing devise_scope block.
- D2: Patra::FinanceAnalytics does NOT exist anywhere in the repo (grepped). ADM1 says "via
  Patra::FinanceAnalytics" → I build it new in lib/patra/finance_analytics.rb (my lane). Data sources,
  mirroring app/services/owner_stats/aggregator.rb definitions (READ only, logic mirrored not edited):
  deposits/cashouts = contact.custom_attributes['patra_finance_logs'] entries (kind/amount/logged_at);
  malformed entries skipped + counted. By-game money = GameAction (action_type load/cashout,
  status=success, amount, agent_game→game) — pure SQL. Per-account finance-log rollups can't be pure SQL
  (jsonb array inside contacts) → batched find_each in chunks.
- D3: "High-risk player" has no existing model/scorer in repo (grepped risk_score/high_risk — nothing).
  Definition used: contact with ≥1 patra_finance_logs entry carrying a non-empty flag_reason (the fraud
  flag the orchestrator/reply_service write). Logged so ADM1 RISK panel semantics are explicit.
- D4: No billing tables exist (patra_billing_subscriptions not in schema, plan_key grep = nothing) →
  ADM1 billing panel renders "billing not initialized"; ADM2 plan/subscription shows "—". Defensive
  table_exists? check so the panel lights up automatically when billing ships.
- D5: HARD BOUND "features gated OFF in features.yml": added account feature `patra_operator_console`
  (enabled: false) at END of features.yml (additive, order preserved). Console MUTATING actions
  (suspend/reactivate/flag-toggle/impersonate/banner post) additionally require env kill-switch
  PATRA_ADMIN_CONSOLE_ACTIONS=true (read in lib/patra/admin_console.rb — no initializer needed, TAB B
  owns initializers). Default = read-only console, all mutations 403. Specs stub the env.
- D6: ADM2 actions implemented in NEW SuperAdmin::PatraAccountsController (panel + suspend/reactivate +
  feature toggle) instead of adding member routes to the existing `resources :accounts` mid-file — S8
  confines my routes to the marked EOF block. Existing accounts_controller/account_dashboard untouched.
- D7: Existing SuperAdmin::PatraDashboardController (JSON stub: counts + system_health) is a patra_*
  controller in my lane → rewritten as the ADM1 HTML command center. `system_health` JSON action kept
  intact (route already exists mid-file; not moved).

## ADM1 — SHIPPED (specs written, unrun)
- Files: lib/patra/finance_analytics.rb (platform/account money+risk scan),
  lib/patra/game_health_query.rb (replicated read-only health logic + matrix builder, shared with ADM3),
  lib/patra/admin_console.rb (env kill-switch for mutations, see D5),
  app/controllers/super_admin/patra_dashboard_controller.rb (rewritten per D7 — HTML command center;
  legacy JSON kept via format.json incl. system_health with AuditLog last_errors untouched),
  app/views/super_admin/patra_dashboard/show.html.erb (Patra-branded panels + 7/30/90d + custom range),
  _navigation.html.erb (Command Center + Audit Trail links; patra_* resources excluded from auto-list),
  features.yml (+patra_operator_console enabled:false — appended at END, order preserved),
  specs: spec/lib/patra/finance_analytics_spec.rb (3-account fixtures incl. malformed entries
  skipped+counted), spec/controllers/super_admin/patra_dashboard_controller_spec.rb.
- N+1 proof: accounts/engagement/integrations panels are single SQL group/subquery statements;
  finance + risk = ONE batched contact scan (find_each batch 500, jsonb arrays can't be SQL-aggregated);
  by-game money = pure SQL over game_actions. No per-account queries anywhere.
- Engagement definitions mirror OwnerStats::Aggregator (source_id='ai_auto' outgoing = AI reply,
  cached_label_list LIKE '%needs-human%' = handoff). Aggregator itself NOT edited (service lane).
- Malformed finance entry = non-hash entry, or deposit/cashout row with unparseable amount/time.
  Screenshot/status rows without kind are normal and silently ignored (matches Aggregator).
- Billing: data_source_exists?('patra_billing_subscriptions') → absent ⇒ "billing not initialized"
  panel (the shipping state); present ⇒ row count + MRR '—' TODO-CONFIG. Panel ordered last (D4).
- ERB note: views with `<%= helper do %>` blocks can't be parsed by plain ERB (no erubi gem locally) —
  plain-ERB "syntax error" on form_with/link_to blocks is a false positive; pre-existing nav partial
  fails the same check unedited. All .rb files ruby -c clean.

## ADM2 — SHIPPED (specs written, unrun)
- Files: app/controllers/super_admin/patra_accounts_controller.rb (NEW controller per D6),
  app/views/super_admin/patra_accounts/show.html.erb (panel + confirm-dialog action forms),
  accounts/show.html.erb (+1 "Patra Control Panel" button), routes member posts in marked block,
  spec/controllers/super_admin/patra_accounts_controller_spec.rb.
- Panel: status badge, plan/subscription '—' (D4 billing absent), player/agent/conversation counts,
  30d net via FinanceAnalytics.account_scan, flagged-player risk, integration health via
  GameHealthQuery (healthy/degraded/down counts), created/last-active (max message created_at),
  last 10 audit rows for the account.
- Actions: suspend / reactivate (flip the VERIFIED enum — no new enforcement built, per VERIFIED
  FACTS; cross-check spec proves a suspended account 401s at /api/v1 via existing
  EnsureCurrentAccountHelper) · toggle any features.yml flag (enable_features!/disable_features!,
  name whitelisted against Featurable::FEATURE_LIST). ALL actions: super-admin only + kill-switch
  (403 when off, audit row count stays 0) + required reason + data-confirm + ADM5 audit BEFORE the
  change + reversible. NO delete path. NO billing mutations (viewing only — logged decision).
- Audit actions recorded: account.suspend, account.reactivate, account.feature_toggle
  (metadata: feature/from/to — booleans only, no secrets).

## ADM3 — SHIPPED (specs written, unrun)
- Logged choice: health_status/session_age_minutes are PRIVATE instance methods inside
  Api::V1::Accounts::Patra::GameHealthController#index — extracting them would mean editing an API
  controller outside the TAB-C lane, so the read-only logic was REPLICATED into
  Patra::GameHealthQuery (same thresholds: failure_count>=3 down, >0 degraded, else healthy) with a
  KEEP-IN-SYNC comment in both the module and this log. The API controller was NOT touched.
- Files: app/controllers/super_admin/patra_game_health_controller.rb (read-only, one query),
  app/views/super_admin/patra_game_health/show.html.erb (matrix rows=accounts cols=games,
  down-first sort + row highlight, per-game summary row, session age, last-checked, last-error
  TEXT only), route `resource :patra_game_health` in marked block, nav link.
- 🔒 Cells render last_connection_message (error text, 255-char truncated by the model) and
  status/timestamps ONLY. Spec asserts the serialized matrix contains neither credential values nor
  credential keys. Never triggers live connections (reads persisted columns only — spec mocks
  .matrix and the builder itself does pure AR reads).
- Specs: spec/lib/patra/game_health_query_spec.rb (threshold parity, matrix shape, down-first sort,
  per-game summary, credential-leak guard), spec/controllers/super_admin/
  patra_game_health_controller_spec.rb (auth + mocked matrix render).

## SECURITY-MODEL (ADM4)
Files: app/controllers/concerns/patra_impersonation_guard.rb (new concern, my lane),
app/controllers/super_admin/patra_impersonations_controller.rb, application_controller.rb (+include,
2 lines), users/_impersonate.erb (REPLACED — see finding below), _navigation.html.erb (indicator+exit),
routes `resource :patra_impersonation` in marked block, spec (.../patra_impersonations_controller_spec.rb).

Requirement-by-requirement:
1. SUPER-ADMIN ONLY — devise authenticate_super_admin! (route layer) + explicit
   `current_super_admin.is_a?(SuperAdmin)` re-check inside #create (session-creation layer).
2. AUDIT BEFORE SESSION — Patra::AdminAudit.record('impersonation.start', admin, target user,
   required reason, IP, timestamp, target_account_ids) runs BEFORE the marker is set and BEFORE the
   SSO link is generated; if the audit insert raises, no marker and no link exist (spec proves it).
3. DISTINCT MARKER — session['patra_impersonation'] = {impersonator_id, target_user_id, started_at,
   expires_at} PLUS the explicit session[:impersonator_id]. Never silent: red banner + exit button
   render in the console nav on every page while active, and every console response carries
   X-Patra-Impersonation header.
4. TIME-BOX — expires_at = 30 minutes, checked by a before_action on EVERY console request
   (concern included in SuperAdmin::ApplicationController). Expired or unparseable expiry ⇒
   auto-exit (marker cleared + 'impersonation.auto_exit' audit row, best-effort rescue so a broken
   audit can never brick the console; manual enter/exit DO hard-fail on audit errors).
5. ONE-CLICK EXIT — DELETE /super_admin/patra_impersonation: 'impersonation.exit' audit row with
   duration_seconds, marker cleared, deliberately NOT behind the kill-switch (an operator must
   always be able to exit).
6. PROMINENT INDICATOR — console-side banner shipped; SPA-side banner is frontend → DEFERRED-FRONTEND
   below documents the exact header + JSON endpoint contract.
7. NEVER IMPERSONATE A SUPER-ADMIN — STI check (`target.is_a?(SuperAdmin)`) ⇒ 403 + audited
   'impersonation.denied_super_admin_target'; the users/_impersonate partial also hides the form.
8. NEVER EXPOSE CREDENTIALS/TOKENS — login uses the EXISTING one-time SSO token (SecureRandom.hex(32),
   5-min Redis TTL, generate_sso_link_with_impersonation). The link/token is handed to the browser
   redirect only — never persisted, never logged (spec asserts the audit row doesn't contain the
   token; ADM5 scrubber would mask 64-char hex anyway). Target passwords/JWTs never touched.
Kill-switch: #create requires PATRA_ADMIN_CONSOLE_ACTIONS=true (default OFF) — 403 with zero rows.

SECURITY FINDING (closed): app/views/super_admin/users/_impersonate.erb previously rendered a raw
`generate_sso_link_with_impersonation` link — UNAUDITED impersonation with no reason, no time-box,
no marker. Replaced with a form into the audited #create flow. Residual: the model method itself
(app/models/concerns/sso_authenticatable.rb) still exists and is callable from console/other code —
model concerns are outside the TAB-C lane ⇒ see DEFERRED-SECURITY.

## ADM4 — DEFERRED-SECURITY (reasoned, not loose)
- SPA token revocation on exit: SSO login issues the SPA its own auth token; exit/expiry clears the
  ADMIN-side marker + audit but cannot revoke the SPA token without editing user/token code outside
  my lane (and Chatwoot tokens have no per-session revocation primitive). Mitigations shipped:
  30-min marker, exit notice tells the operator to close impersonated tabs, one-time 5-min SSO token.
  Proper fix (HANDOFF-B): rotate target user tokens on impersonation exit.
- sso_authenticatable#generate_sso_link_with_impersonation remains callable outside the audited flow
  (model concern, not my lane). UI path closed. Proper fix (HANDOFF-B): make the method require an
  audit context or delete it in favor of the audited controller.
- DB-level immutability for patra_admin_audit_logs (REVOKE UPDATE/DELETE) — run once via psql by
  Genius: `psql $DATABASE_URL -c "REVOKE UPDATE, DELETE ON patra_admin_audit_logs FROM <app_role>;"`

## ADM6 — SHIPPED (specs written, unrun)
- AUDIT FINDING (good news): the tenant-side banner pipeline ALREADY EXISTS END-TO-END —
  PlatformBanner model (enum info/warning/error, active scope) → super_admin Administrate CRUD →
  DashboardController#app_config ACTIVE_PLATFORM_BANNERS (app/controllers/dashboard_controller.rb:84-93)
  → window.globalConfig (app/javascript/shared/store/globalConfig.js:27) →
  StatusBanner.vue (app/javascript/dashboard/components/app/StatusBanner.vue — renders + per-update
  dismissal). NO missing SPA component ⇒ NO DEFERRED-FRONTEND contract needed for banners.
- Added: platform_banners_controller.rb now audits create/update/destroy via Patra::AdminAudit
  ('platform_banner.create|update|destroy', message excerpt as reason, permitted attrs as metadata,
  update/destroy carry target deep-link). Audit row records the ATTEMPT before Administrate performs
  the mutation (decision: attempts are auditable events; append-only trail).
- Nothing auto-posts: banners change only via these explicit super-admin actions (verified: only
  write path is this Administrate controller; `active` defaults true on create — creation IS the
  explicit post action).
- Decision: banner posting NOT placed behind the PATRA_ADMIN_CONSOLE_ACTIONS kill-switch — it is a
  pre-existing capability; TAB-C only ADDED auditing (removing capability overnight = riskier).
- ⚠ OPERATOR NOTE for Genius: both the posting UI and the tenant read path are gated by
  ChatwootApp.chatwoot_cloud? (enterprise dir + GlobalConfig DEPLOYMENT_ENV == 'cloud'). I cannot
  verify Render's DEPLOYMENT_ENV from here — if banners don't show in prod, check
  `psql $DATABASE_URL -c "SELECT value FROM installation_configs WHERE name='DEPLOYMENT_ENV';"`.
- Spec: spec/controllers/super_admin/platform_banners_controller_spec.rb (cloud gate 404, audited
  create/update/destroy, tenant read path shows active-only banners).

## ADM7 FINDINGS
HOW SUSPENSION BLOCKS (verified by reading code + existing spec, not by running):
- Enforcement lives in app/controllers/concerns/ensure_current_account_helper.rb:11 —
  `render_unauthorized('Account is suspended') and return unless account.active?` inside
  ensure_current_account, which runs whenever a controller calls current_account.
- Included by Api::V1::Accounts::BaseController (line 3) ⇒ ALL /api/v1/accounts/:id/* requests,
  and by conversations/direct_uploads_controller. render_unauthorized = JSON {error}, HTTP 401
  (request_exception_handler.rb:26-28).
- Mid-session suspension bites on the NEXT request: the check runs per-request on params[:account_id];
  no token/session invalidation needed. Existing spec spec/controllers/api/base_controller_spec.rb:97-118
  proves 401 for suspended accounts (incl. the no-access DoubleRender edge).
- Public widget page widgets_controller.rb:62 and website_token_helper.rb:10 also check active? (401).
- ADM2 adds a cross-check spec (suspend via console ⇒ /api/v1 401) + the new safety-net spec below.

GAPS FOUND AND CLOSED TONIGHT (non-hot Patra custom controllers — ADM7 explicitly allows the guard):
1. POST /widget/patra/messages (Widget::MessagesController — Patra embeddable widget): created
   contacts/conversations/messages with NO suspension check. Now 401 'Account is suspended'
   (mirrors widgets_controller's existing check). Spec proves no Message row is created.
2. GET/POST /help/:account_id/* (HelpCenterController — Patra public help center): served articles +
   accepted feedback for suspended accounts. find_account now filters non-active ⇒ 404; also fixed a
   latent 500 (nil account NoMethodError) in show/search/feedback ⇒ now 404.

## SECURITY-GAPS (open — documented, NOT guarded tonight, with reasons)
- SG-1 Inbound platform webhooks process events for suspended accounts: /webhooks/telegram,
  /webhooks/zernio (ProcessZernioInboundJob), /webhooks/messenger, /webhooks/fb_reply,
  /webhooks/tiktok, /webhooks/shopify, /webhooks/instagram, /webhooks/whatsapp, /webhooks/sms,
  /webhooks/line. Controllers ack + enqueue jobs; account resolution happens deep in jobs/services —
  for FB that path runs through facebook/chatwoot_bridge_service.rb (HOT FILE) and the Bella reply
  pipeline, i.e. a suspended tenant's inbox keeps ingesting AND the bot may keep replying/executing.
  NOT guarded tonight because: webhook controllers are outside the TAB-C lane, the account lookup
  point is inside TAB-A/B-owned services (some hot), and a wrong guard there drops legitimate
  multi-account events. HANDOFF-B below proposes the guard point (inside each inbound job, right
  after account/channel resolution: `return if account.suspended?`).
- SG-2 (residual, ADM4): sso_authenticatable#generate_sso_link_with_impersonation remains callable
  outside the audited controller flow (model concern outside lane). UI path replaced tonight.

## SECURITY-GAPS — none in TAB-C-shipped surfaces (self-review): every new mutating endpoint is
super-admin-gated + kill-switch-gated + audited; new read surfaces render no credentials.

## DEFERRED-FRONTEND
- IMPERSONATION INDICATOR IN THE SPA (the only frontend deferral — banners turned out fully wired).
  The console-side red banner ships tonight; the SPA must additionally show "you are being viewed /
  acting as" while an operator is impersonating. Backend contract SHIPPED and stable:
  1. Header: every super-admin response while active carries
     `X-Patra-Impersonation: active; target_user_id=<id>; expires_at=<iso8601>`.
  2. Status endpoint: `GET /super_admin/patra_impersonation` (super-admin session cookie) returns
     `{active, impersonator_id, target_user_id, started_at, expires_at}` or `{active:false}`.
  3. The SSO login URL the impersonated tab receives carries `&impersonation=true` (existing param —
     the SPA can persist it at login and render a banner without any new backend call).
  Suggested SPA work (TAB A / future): on login with impersonation=true, store a flag + render a
  persistent banner; optionally poll (2) for expiry countdown.

## HANDOFF-B
- HB-1 (SG-1): add `return if account.suspended?` (or .active? guard) inside each inbound webhook JOB
  right after account/channel resolution (Webhooks::TelegramEventsJob, ProcessZernioInboundJob, FB
  bridge path, tiktok/shopify/instagram/whatsapp/sms/line). Controllers/jobs/services are TAB-B lane;
  FB path touches HOT chatwoot_bridge_service — needs owner care.
- HB-2 (ADM4 residual): rotate target-user tokens on impersonation exit + make
  generate_sso_link_with_impersonation unreachable outside the audited controller
  (sso_authenticatable.rb is a model concern outside TAB-C lane).
- HB-3 (ADM5 hardening): DB-level append-only:
  `psql $DATABASE_URL -c "REVOKE UPDATE, DELETE ON patra_admin_audit_logs FROM <app_db_role>;"`

## DEFERRED-SECURITY

## SPECS-UNRUN (10 files total: 7 controller + 3 lib)
- ALL TAB-C specs are written but UNRUN locally: `bundle exec rspec` fails with "command not found:
  rspec" — the gem bundle is not installed in this Windows checkout (exit 127 verified 2026-06-10).
  Setup to run them:
  1. `bundle install` (needs Ruby + Postgres headers; on Render/CI this is already done)
  2. `RAILS_ENV=test bundle exec rails db:create db:schema:load` (loads my additive migration too)
  3. `bundle exec rspec spec/lib/patra/ spec/controllers/super_admin/patra_admin_audit_logs_controller_spec.rb`
  Every TAB-C file passes `ruby -c`. No pass is claimed for any spec below — they are written-not-run.

## ADM5 — SHIPPED (specs written, unrun)
- Files: db/migrate/20260610090000_create_patra_admin_audit_logs.rb (ADDITIVE create_table),
  app/models/patra_admin_audit_log.rb (readonly? after persist + before_destroy raise),
  lib/patra/admin_audit.rb (Patra::AdminAudit.record + deep credential scrubber),
  app/dashboards/patra_admin_audit_log_dashboard.rb (FORM_ATTRIBUTES = [], COLLECTION_FILTERS
  action:/admin:/since:/before:), app/controllers/super_admin/patra_admin_audit_logs_controller.rb
  (newest-first default order), routes only: [:index, :show] in marked block.
- Append-only contract: ONLY write path is Patra::AdminAudit.record; model raises
  ActiveRecord::ReadOnlyRecord on update/destroy; no create/update/destroy routes (spec asserts
  RoutingError). DB-level immutability (REVOKE UPDATE/DELETE on patra_admin_audit_logs) = documented
  FUTURE HARDENING for Genius/psql — app cannot do it safely in a migration shared across envs.
- Scrubber: masks values under keys matching secret/password/credential/token/api_key/auth/session/
  cookie/otp (case-insensitive) at ANY depth, and any string value that looks like an opaque ≥32-char
  hex/base64 blob even under innocent keys.
- target_type stores base_class (SuperAdmin target would store 'User') so polymorphic lookups work.

## FINAL PROOFS (verified by me 2026-06-10, commands run in this session)
1. LANES — `git log --grep '^patra-feat:' 5bfb2862a..HEAD` = 8 TAB-C commits; union of their files
   (36 paths) is exactly: super_admin controllers + new concern + dashboards + new model + lib/patra +
   super_admin views + features.yml + routes.rb + 1 additive migration + new spec files + this log +
   the two ADM7-sanctioned guards (help_center_controller.rb, widget/messages_controller.rb — non-hot,
   non-WIP, explicit ADM7 allowance). ZERO edits to: 4 hot files, intent/RAG/bella files,
   app/services/**, app/javascript/** /.vue/public/vite, Gemfile, config/initializers, sibling logs,
   owner-WIP files. (Other files in the full rollback-diff belong to TAB A/patra-launch commits.)
2. MIGRATIONS — one file, 20260610090000_create_patra_admin_audit_logs.rb: create_table + 4 add_index,
   additive only, no alters of existing tables.
3. ROUTES — per-commit diff of config/routes.rb across all TAB-C commits = additions only, every line
   inside the `== PATRA TAB-C ROUTES ==` marked EOF block (block created by ADM5 commit, D1).
4. FEATURES — features.yml parses (64 features, no duplicate names), patra_operator_console
   enabled:false appended at end (order preserved); mutations additionally env-gated OFF (D5).
5. CREDENTIALS — Select-String over all TAB-C files: zero `.credentials` access without `safe_`;
   every 'credentials' mention is a 🔒 comment, a spec fixture, or the leak-guard spec. No admin
   view/controller/log/audit renders or transmits credential values; ADM5 scrubber masks
   credential-shaped metadata; ADM3 spec asserts the matrix JSON contains no credential key/value.
6. SYNTAX — ruby -c on all 28 TAB-C .rb files: 0 failures. (ERB block-helpers not plain-ERB-parseable
   locally — see ADM1 note; .erb files reviewed by hand.)
7. SPECS — 10 new spec files, NOT RUN (S6 — no local bundle, exit 127 verified). No pass claimed.

## HANDOFFS — see HANDOFF-B section above (HB-1 webhook suspension guards, HB-2 token rotation on
impersonation exit, HB-3 DB-level audit immutability). No HANDOFF-A items.
