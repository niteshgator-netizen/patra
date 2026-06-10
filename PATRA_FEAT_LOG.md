# PATRA_FEAT_LOG.md — TAB C: SUPER-ADMIN OPERATOR CONSOLE

(Morning summary will be inserted at top when run completes.)

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
- [ ] ADM3 — integration health matrix
- [ ] ADM4 — impersonation / support-login
- [ ] ADM6 — platform banner
- [ ] ADM7 — suspension safety-net
- [ ] FINAL — proofs + morning summary

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

## SECURITY-MODEL (ADM4) — filled when ADM4 ships

## ADM7 FINDINGS — filled when ADM7 done

## SECURITY-GAPS

## DEFERRED-FRONTEND

## DEFERRED-SECURITY

## SPECS-UNRUN
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

## HANDOFFS
