# PATRA FINAL MEGA — RUN LOG

**ROLLBACK HASH (state before this run):** `fa02e1bf5a65d1aad3c71acd769b037f30ddb375`

Run date: 2026-06-12. Branch: main. Committed per phase as `patra-final:`, NEVER pushed.

---

## PHASE 1 — EE LICENSE CLEANUP (G48)

### How the banner works (verified by reading code this session)

1. `config/schedule.yml` cron (daily 00:00 UTC) → `Internal::TriggerDailyScheduledItemsJob` (`app/jobs/internal/trigger_daily_scheduled_items_job.rb:15`) → `Internal::CheckNewVersionsJob`.
2. That job is extended by EE (`enterprise/app/jobs/enterprise/internal/check_new_versions_job.rb`): it phones home to `hub.2.chatwoot.com`, stores the plan (`INSTALLATION_PRICING_PLAN`), then runs `Internal::ReconcilePlanConfigService`.
3. `ReconcilePlanConfigService` (enterprise/app/services/internal/reconcile_plan_config_service.rb) — only when plan is `community` (Patra's plan; no subscription):
   - **Banner**: if any branding `InstallationConfig` row differs from stock Chatwoot values in `enterprise/config/premium_installation_config.yml` (INSTALLATION_NAME, BRAND_NAME, BRAND_URL, WIDGET_BRAND_URL, LOGO, LOGO_DARK, LOGO_THUMBNAIL, TERMS_URL, PRIVACY_URL, DISPLAY_MANIFEST) → sets Redis key `CHATWOOT_CONFIG_RESET_WARNING` → super admin settings page shows "Unauthorized premium changes detected".
   - **Reset**: it then OVERWRITES those rows back to stock Chatwoot values. **This is the root cause of G40** (brandName/installationName showing "Chatwoot" — someone set them to Patra, the nightly job reset them).
   - **Feature kill**: force-disables the 7 flags in `enterprise/config/premium_features.yml` on EVERY account, EVERY night.
4. The Redis key is deleted at the start of every run and re-created only if a mismatch still exists. So: banner present ⇒ a branding row differed at the last nightly run.

**Claim labels**: code chain = verified by me now (files read). That the job fires nightly on Render = assumption (cron is registered; the banner's existence is evidence it runs). Current prod DB values = NOT verified (postgres MCP couldn't connect: "SSL/TLS required") — VERIFY commands below.

### EE feature classification (the 7 nightly-killed premium flags)

| Feature | Class | Decision | Notes |
|---|---|---|---|
| `disable_branding` | (b) own implementation | leave disabled | Patra branding is code-level in MIT core (views/assets). The EE flag only gates config-driven white-labeling. Nothing in Patra reads this flag. |
| `audit_logs` | (b) own implementation | leave disabled | Patra has its own audit trail: `PatraAdminAuditLog` (`app/models/patra_admin_audit_log.rb`), super-admin UI + account API (`app/controllers/api/v1/accounts/patra_audit_logs_controller.rb`). EE `audited`-gem logs not needed. Phase 2c nav entry points at the Patra audit UI, not the EE page. |
| `sla` | **(c) load-bearing, no equivalent** | **DO NOT touch — needs license** | ALL SLA backend code lives in `enterprise/` (sla_policy.rb, applied_sla.rb, sla_event.rb, 3 jobs, evaluate service, 2 controllers, policy, drop — ~12 files + hooks). The nightly job force-disables the `sla` flag, so even manual enabling dies within 24h. See Phase 4. |
| `custom_roles` | (a) not used | leave disabled | Deliberately hidden in nav (prior decision). |
| `captain_integration` | (b) own implementation | leave disabled | Patra has Bella (Grok/Anthropic/DeepSeek stack). Captain unused. |
| `csat_review_notes` | (a) not used | leave disabled | Plain CSAT works without it. |
| `conversation_required_attributes` | (a) not used | leave disabled | Not part of any Patra flow. |

"Leave disabled" = the nightly job already keeps these off; Patra does not depend on any of them, so there is nothing to disable in code and no gate is hacked.

### SLA — honest licensing implication

- SLA is Chatwoot EE-gated twice: (1) the `sla` account flag is force-disabled nightly on the community plan; (2) all backend code is in `enterprise/` under the Chatwoot Enterprise license, which requires a paid subscription for production use.
- **Options**: (i) buy a Chatwoot EE license — cleanest; (ii) build a Patra-own SLA (own tables e.g. `patra_sla_policies`, own Sidekiq checker job, own report) — estimate: roughly the scope of those ~12 backend files written clean-room, i.e. a multi-day focused build (this is my estimate, not a measured number); (iii) live without SLA.
- Per the run instructions, **no gate was hacked and Phase 4 builds nothing** — see Phase 4 report.
- Note: patra-fix2 (`e83ae98`) restored SLA settings to nav. That nav item is feature-flag-gated, so after each nightly reconcile it disappears again. Not a Patra bug — it's the EE enforcement.

### How the banner goes away legitimately

The banner is ONLY about the 10 branding InstallationConfig rows. Plan:
1. Keep DB branding rows at stock Chatwoot values (the nightly job has likely already reset them — verify below).
2. Do Patra-visible branding at MIT-core code level (Phase 5d does exactly this for brandName/installationName surfaces).
3. With rows stock, `premium_config_reset_required?` is false → key deleted next nightly run → banner gone.

**VERIFY (Genius, on Render shell):**
```
bundle exec rails runner "puts InstallationConfig.where(name: %w[INSTALLATION_NAME BRAND_NAME BRAND_URL WIDGET_BRAND_URL LOGO LOGO_DARK LOGO_THUMBNAIL TERMS_URL PRIVACY_URL DISPLAY_MANIFEST]).map { |c| \"#{c.name} = #{c.value.inspect}\" }"
```
Success looks like: every row matching `enterprise/config/premium_installation_config.yml` stock values (INSTALLATION_NAME = "Chatwoot", etc.). If any row differs, that's what keeps re-arming the banner.

**Clear the banner immediately (optional, safe — it's just the Redis flag; it only comes back if rows still mismatch):**
```
bundle exec rails runner "Redis::Alfred.delete(Redis::Alfred::CHATWOOT_INSTALLATION_CONFIG_RESET_WARNING)"
```

**Check account 2 premium flags (expected: all false after any nightly run):**
```
bundle exec rails runner "a=Account.find(2); %w[sla audit_logs disable_branding custom_roles captain_integration csat_review_notes conversation_required_attributes].each { |f| puts \"#{f}: #{a.feature_enabled?(f)}\" }"
```

### Phase 1 code changes
None. The legitimate fix is operational (commands above) + Phase 5d's code-level branding. No EE file was modified.

---

## PHASE 2 — NAVIGATION REORG

### Nav map: BEFORE → AFTER

| Item | Before | After |
|---|---|---|
| Reports (rail) | → `/patra/reports` directly | → `/patra/reports-hub` (new hub page, sweepstakes report = featured card) |
| More → Broadcasts | → `campaigns_livechat_index` (wrong target — old Campaigns) | → `patra_broadcast_list` (the real Broadcasts UI), admin-gated |
| More → Audit Logs | → `auditlogs_list` (EE page, feature-gated OFF — dead link) | → `patra_audit_logs` (new Patra page over Patra's own AuditLog model), admin-gated |
| More → Cashier Queue | already present (`patra_cashier_queue`) | unchanged — 2b was already satisfied by a prior fix; verified route + entry both exist |
| More → Backup Pages | already present (`patra_backup_pages`) | unchanged — same |
| Settings → Auto-routing | "Agent Assignment", gated on EE `advanced_assignment` flag (hidden in practice) | labeled **Auto-routing**, gated on `assignment_v2` (core, default-on — same flag as the route itself) |
| Settings → Custom Attributes | hidden (H.10) | restored → `attributes_list` (the real persisted page; `patra_custom_attributes` builder is a non-persisting demo — left URL-only) |
| Settings → Macros | hidden (H.10) | restored → `macros_wrapper` |
| Settings → Audit Logs | hidden (H.10) | added → `patra_audit_logs` |
| Custom Roles / Security / Conversation Workflow / Campaigns | hidden | still hidden (deliberate) |

### 2a Reports hub — new files
- `app/javascript/dashboard/routes/dashboard/patra/PatraReportsHub.vue` (new): featured Sweepstakes Reports card + grouped cards: Owner Live Overview (`account_overview_reports`), Agent Leaderboard (`patra_leaderboard`), Sweeps Financial (`patra_sweeps_report`), CSAT (`csat_reports`), Agents (`agent_reports`), SLA (`sla_reports`), Conversations (`conversation_reports`), Inboxes (`inbox_reports`), Labels (`label_reports`), Teams (`team_reports`). One-line plain-English description per card. Admin-only cards hide for agents (matches target-route permissions). Patra tokens (n-slate/n-weak/n-solid), works in both themes.
- Route `patra/reports-hub` → `patra_reports_hub` registered in `dashboard.routes.js`.

### 2c Audit logs page — new files
- `app/javascript/dashboard/routes/dashboard/patra/PatraAuditLogs.vue` (new): last 100 entries from `GET /api/v1/accounts/:id/patra_audit_logs` (existing controller), table with time/action/target/details/IP.
- `app/javascript/dashboard/api/patraAuditLogs.js` (new API client).
- Route `patra/audit-logs` → `patra_audit_logs` (admin) in `dashboard.routes.js`.

### 2d Macros copy
- `app/javascript/dashboard/i18n/locale/en/macros.json` MACROS.DESCRIPTION: Chatwoot email-transcript text → Patra voice ("...label a chat, assign it to a team, update a player attribute...").

### Files changed in Phase 2
- `app/javascript/dashboard/components-next/sidebar/Sidebar.vue` (nav edits above)
- `app/javascript/dashboard/routes/dashboard/dashboard.routes.js` (2 routes)
- `app/javascript/dashboard/i18n/locale/en/macros.json` (copy)
- 3 new files (hub page, audit page, api client)

---

## PHASE 3 — AGENT FEEDBACK (agents → owner, never players)

### Backend (all `ruby -c` clean)
- **Migration** `db/migrate/20260612090000_create_patra_agent_feedbacks.rb` — additive only: `patra_agent_feedbacks` (account_id, user_id, conversation_id nullable, contact_id nullable, body, category int enum, status int enum, timestamps) + 3 indexes. No FKs, no changes to existing tables. NOTE: `db/schema.rb` not regenerated locally (no local DB) — Render's `db:migrate` applies it on deploy.
- **Model** `app/models/patra_agent_feedback.rb` — enums `category: bug/player_issue/suggestion/other`, `status: new/seen` (prefixed — `new` clashes with Ruby otherwise). `after_create_commit :notify_admins` creates one in-app `Notification` per account admin (skips the author), wrapped in rescue so notification failure can never break feedback creation. `push_event_data` provided for the notification payload.
- **Controller** `app/controllers/api/v1/accounts/patra_agent_feedbacks_controller.rb` — index (agents: own only; admins: all + category/status filters, newest first, cap 200), create (resolves conversation by display_id, contact by id, both scoped to the account), update (admin-only, status only).
- **Route** `config/routes.rb`: `resources :patra_agent_feedbacks, only: [:index, :create, :update]` (next to patra_audit_logs).
- **Association** added in `config/initializers/patra_model_associations.rb` (house pattern): `Account has_many :patra_agent_feedbacks`.
- **Notification type** `patra_agent_feedback: 10` in `app/models/notification.rb` mirroring the existing `patra_all_payment_handles_dead: 9` precedent: title in `config/locales/en.yml`, body from feedback, fcm guard; early-returns added in push/email notification services (in-app only — push/email flags also default off for new types).
- **Bug found & fixed while wiring this**: `Notification::RemoveDuplicateNotificationJob` deduped on `(user_id, primary_actor_id)` WITHOUT `primary_actor_type` — a Conversation and any non-conversation actor sharing a numeric id counted as duplicates and one notification was silently destroyed. Now scoped by type as well.

### Frontend
- `app/javascript/dashboard/api/patraAgentFeedback.js` (new client).
- `app/javascript/dashboard/routes/dashboard/patra/PatraFeedback.vue` (new): agents see a send form (category select + body, conversation/contact pre-fill via query params) + their own entries; admins see the inbox — newest first, category/status filters, New/Seen pill, mark seen/new, links to the conversation and contact. Route `/patra/feedback` → **the audited 404 URL is now a real page**.
- Sidebar (More group): "Send Feedback" for agents / "Agent Feedback" for admins.
- Conversation header ⋯ menu (`MoreActions.vue`): "Send feedback" → `/patra/feedback?conversation_id=…&contact_id=…`.
- Notification click (`InboxList.vue`): `patra_agent_feedback` notifications mark read and open the feedback inbox instead of trying to open a (nonexistent) conversation.
- i18n: notification TYPE_LABEL in `generalSettings.json`, title in `en.yml`.

### VERIFY (Genius, after deploy + migration)
```
# as an agent: send feedback from the sidebar, then as admin check /patra/feedback and the bell icon
bundle exec rails runner "puts PatraAgentFeedback.count"
```

---

## PHASE 4 — SLA SEED: NOT BUILT (EE-blocked, as instructed)

Phase 1 finding (verified in code): SLA is Chatwoot Enterprise-gated on two levels —
1. The `sla` account feature flag is in `enterprise/config/premium_features.yml` and is **force-disabled on every account, every night** by `Internal::ReconcilePlanConfigService` while the install is on the free community plan.
2. Every SLA backend file (SlaPolicy, AppliedSla, SlaEvent models, the evaluation jobs/service, both controllers) lives in `enterprise/` under the Chatwoot Enterprise license — production use requires a paid subscription.

Consequence: a seed that creates `sla_policies` rows + automation rules would write data into a feature whose flag dies within 24 hours and whose runtime jobs are license-restricted. Per run instructions ("if EE-blocked, build nothing extra"), **no seed/migration was created**.

**If Genius buys a Chatwoot EE license later**, the seed is 4 manual steps (or ask for the seed then — Genius's numbers preserved here):
- Policy "FB first response": first_response_time_threshold = 300 (5 min)
- Policy "Telegram first response": first_response_time_threshold = 600 (10 min)
- Automation rule: conversation_created + inbox = FB inbox (5) → add_sla "FB first response"
- Automation rule: conversation_created + inbox channel = Telegram → add_sla "Telegram first response"

Alternative if no license: build a Patra-own SLA (own `patra_sla_*` tables + Sidekiq checker + the already-working conversation chips) — multi-day build, see Phase 1 estimate. PROPOSED, not built.

---

## PHASE 5 — BUG CLOSURES

### 5a (G59) — dead ActionCableBroadcastJobs
- `app/jobs/action_cable_broadcast_job.rb`: `prepare_broadcast_data` now (1) skips when `data[:id]` is blank (nil display_id — the audited cause), (2) rescues `ActiveRecord::RecordNotFound` for both the Account and Conversation lookups → warn-log + drop, never die. Websocket refreshes are best-effort by nature.
- `script/patra_cleanup_nil_display_ids.rb` (new): REPORT-ONLY — counts + lists conversations with NULL display_id (id, account, inbox, contact, created_at). No mutation.
- **Genius runner (report script):** `bundle exec rails runner script/patra_cleanup_nil_display_ids.rb`

### 5b (G58) — New User form autofill
- Cause: the browser autofilled saved credentials (the form pattern-matched a login form). Administrate's default field partials are now overridden: `app/views/fields/password/_form.html.erb` (autocomplete="new-password", explicit blank value) and `app/views/fields/string/_form.html.erb` (autocomplete="off"). Affects all super-admin forms — desirable.

### 5c (G53) — Account show custom_attributes
- `app/views/super_admin/accounts/_custom_attributes_table.html.erb` (new): key/value table, values > 80 chars collapse behind a `<details>` expander. Wired in `accounts/show.html.erb` (special-case for the `custom_attributes` attribute only; everything else renders as before).

### 5d (G40) — brandName/installationName say "Chatwoot"
- **Root cause (Phase 1):** nightly EE reconcile resets the InstallationConfig rows to stock on the community plan. Writing 'Patra' into the DB rows would re-arm the "unauthorized premium changes" banner.
- **Fix (code-level, MIT core):** `app/controllers/dashboard_controller.rb` merges `PATRA_BRANDING_OVERRIDES` (INSTALLATION_NAME/BRAND_NAME → 'Patra') into the dashboard `globalConfig` — the dashboard now always brands as Patra regardless of DB rows, and the EE banner stays un-triggered. Also `config/installation_config.yml` BRAND_NAME default → 'Patra' (fresh installs only; ConfigLoader never overwrites existing rows).
- **Runner the task asked for** (sets the prod DB rows — KNOW THE TRADE-OFF: the nightly EE job will reset them and re-show the banner; with the code fix above this runner is NOT needed for the dashboard, only emails/widget read the DB rows):
```
bundle exec rails runner "%w[INSTALLATION_NAME BRAND_NAME].each { |k| InstallationConfig.find_by(name: k)&.update!(value: 'Patra') }; GlobalConfig.clear_cache"
```
- Recommendation: do NOT run it; if email branding matters, that needs the same code-level treatment in mailers (PROPOSED).

### 5e (G44) — super admin player search
- New read-only page `/super_admin/patra_players` (`patra_players_controller.rb` + view + route + "Player Search" nav item in the Patra console section). Searches contacts by name/email/phone/identifier AND GameAction.game_username (ILIKE, cap 50), shows account link, contact link into the live app, blocked flag, successful load/cashout totals per contact.

### 5f — "Add sweepstakes pack" dead click
- Re-verified the whole chain in source: button → `seedSweepstakesPack` → `store.dispatch('createCannedResponse')` → `CannedResponseAPI.create` → store ADD_CANNED; all i18n toast keys exist (SUCCESS/NONE_ADDED/ERROR/SEEDING). Chain is wired (verified by reading, not by clicking).
- **Real wedge found & fixed:** if anything threw mid-seed, `seedingPack` stayed `true` forever → every later click silently dead (matches the audit symptom). The loop now sits in try/finally; the flag always resets and a toast always fires (`canned/Index.vue`).
- Likely audit-time factor: stale vite bundle (frontend changes need built bundles committed — this run rebuilds at the end).

### 5g (G45) — malformed finance entries
- `lib/patra/finance_analytics.rb`: new READ-ONLY `malformed_report` (mirrors the scan's classification exactly: non-list log / non-hash entry / money row with unparseable amount or time; cap 200 rows).
- New page `/super_admin/patra_malformed_finance` (controller + view + route): account link, contact link, reason, raw logged_at, raw entry snippet. NO mutation anywhere.
- Both "N malformed finance entries skipped" warnings (Command Center + account control panel) are now links to that page.
