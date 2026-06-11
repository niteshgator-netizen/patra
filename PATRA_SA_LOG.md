# PATRA SA MEGA RUN LOG

**ROLLBACK HASH (start of run):** `665b6985de6b9f71e15ab0918f805af137e1bc97`
**Branch:** `patra-feat` (worktree — never touches main patra folder)
**Date:** 2026-06-11

> ⚠️ **MIGRATIONS:** If any migrations are listed in the MIGRATIONS section below, Genius must run `rails db:migrate` on Render after deploy (Web Service shell). Check that section before deploying.

---

## RUN STATUS

| Phase | Status | Commit |
|---|---|---|
| 0 — Double audit | IN PROGRESS | — |
| 1 — Super admin owner console | pending | — |
| 2 — Bug fixes | pending | — |
| 3 — Empty state + theme cleanup | pending | — |
| 4 — Agent feature pack | pending | — |
| 5 — Owner analytics pack | pending | — |
| 6 — Mockup gaps | pending | — |
| 7 — Typography + de-AI polish | pending | — |
| 8 — Lag profiling pass 2 | pending | — |

---

## PHASE 0 — DOUBLE AUDIT (read-only)

### 0a. Super Admin Inventory

64 routes total: 55 stock Chatwoot (Administrate CRUD + console) + 9 Patra TAB C custom routes (routes.rb:828-902, TAB C block at :888-903).

| Screen | Stock vs Patra | Works/Broken (static) | Verdict |
|---|---|---|---|
| Dashboard (`/super_admin`) | Stock | works | restyle |
| Accounts CRUD | Stock | works | restyle |
| Users CRUD | Stock | works | restyle |
| Account Users | Stock | works | restyle |
| Access Tokens (read-only) | Stock | works | restyle, demote in sidebar |
| Installation Configs (app_config) | Stock | works | restyle |
| Agent Bots CRUD | Stock | works | restyle, demote |
| Platform Apps CRUD | Stock | works | restyle, demote |
| Platform Banners CRUD | Stock (cloud) | works | restyle — reuse for banner quick-action |
| App Config (vite page) | Stock | works | restyle |
| Push Diagnostics | Stock | works | demote (utility) |
| Instance Status | Stock | works | demote (utility) |
| Settings / refresh | Stock | works | demote (utility) |
| Feature Flags JSON API | Stock | works | keep (backend for gating UI) |
| **Command Center** (`patra_dashboard`) | **Patra TAB C** | works | visual reference for Phase 1 |
| **Account Control Panel** (`patra_accounts/:id` + suspend/reactivate/toggle_feature) | **Patra TAB C** | works, gated by `PATRA_ADMIN_CONSOLE_ACTIONS` | extend (quick actions already exist!) |
| **Game Health Matrix** | **Patra TAB C** | works | keep |
| **Impersonation** (30-min time-boxed, audited) | **Patra TAB C** | works | keep — wire into quick actions |
| **Audit Trail** (read-only Administrate) | **Patra TAB C** | works | keep |

Key facts:
- Layout: `app/views/layouts/super_admin/application.html.erb`; nav: `app/views/super_admin/application/_navigation.html.erb` (already has Patra P logo + TAB C links + red impersonation banner).
- Styling: stock Administrate SCSS (`app/assets/stylesheets/administrate/`) + `custom_styles.scss` override hook + inline CSS in TAB C views (`.patra-cc`, `.patra-gh`, `.patra-acct`, purple #534AB7).
- Billing/plan models: **NONE**. Command Center has defensive `patra_billing_subscriptions` table check (patra_dashboard_controller.rb:118-131) — panel auto-activates when billing ships.
- features.yml: 64 flags; flag 64 = `patra_operator_console` (enabled: false, chatwoot_internal). Audited toggle path exists: `POST /super_admin/patra_accounts/:id/toggle_feature` (patra_accounts_controller.rb:55-66, requires reason + env gate, writes PatraAdminAuditLog).
- Suspend/reactivate/impersonate/feature-toggle quick actions ALREADY EXIST in TAB C — Phase 1d is mostly surfacing them ≤2 clicks from Command Center, not building.

### 0b. Mockup + Existing-Machinery Audit

Mockups found (repo root + docs):
| File | Depicts | Phase |
|---|---|---|
| PATRA_APP_final.html | full app: dashboard, inbox, leaderboard, vault, contacts, games, AI training, settings | all |
| patra-inbox-v5.html | inbox, composer, presence/typing, SLA timer strip, collision UI | 4b/4c |
| patra-contacts.html | contacts, player vault | — |
| patra-games.html | games grid, player ops | — |
| patra-dashboard-v2.html | owner KPIs, revenue bars, heatmap, agent leaderboard podium, flagged feed | 5b/5c/5d |
| patra-ai-training.html | RAG training queue | (Rules Engine lane — out of scope) |
| patra-settings.html | settings incl. canned response editor | 4a |

Gap table:
| Feature | In Chatwoot fork? | In Patra UI? | Plan |
|---|---|---|---|
| Canned responses | YES full (model + Vuex + MentionBox + ReplyBox wiring) | "/" autocomplete wired; mgmt UI stock | extend: restyle mgmt UI, seed sweepstakes pack |
| CSAT | YES models/toggle/reports; public survey page needs verify | partial | enable + verify survey page branding (5a) |
| Help Center/portal | YES full | partially rebranded | verify + log (6a) |
| Auto-assignment | YES (AssignmentPolicy, round-robin, fair distribution, assignment_v2 flag) | config UI partial/hidden | surface + restyle (4d) |
| Reports | YES (api/v2 reports, Chart.js 4.4.4 + vue-chartjs 5.3.1, Leaderboard.vue exists!) | partial | extend (5b-5d) |
| SLA | **NO models** — sla_activity_message_handler.rb references missing SlaPolicy | mockup only | build minimal (4c) |
| Typing/presence | YES RoomChannel presence.update + typing events | typing UI partial | extend (4b) |
| Intent in custom_attributes at assignment | NO — orchestrator writes additional_attributes['pending_load_intent'] post-routing | — | 4d by-intent routing = PROPOSED |
| GameAction | YES complete (action_type, amount decimal(12,2), status, metadata jsonb, executed_at) | — | read-only analytics source (5b/5d) |
| Patra tokens | patra-themes.css (40+ tokens, data-theme mechanism) | yes | use everywhere |
| Theme toggles | App.vue `patra-theme-fab` + useAppearanceHotKeys + profile settings | MULTIPLE strays | consolidate (3b) |

## PHASE 1 — SUPER ADMIN OWNER CONSOLE

### Changes
- **1a Restyle**: New shared token sheet `app/views/super_admin/application/_patra_admin_styles.html.erb` (--patra #6E56CF family, Space Grotesk/Inter/JetBrains Mono via Google Fonts — same pattern as patra-themes.css:1; dark mode via prefers-color-scheme). Loaded in Administrate layout + login page. Sidebar regrouped into PATRA / PLATFORM / UTILITIES sections; P-logo now token-colored; login page copy → "Patra Owner Console". Command Center + Account Control inline purple #534AB7 → var(--patra). Hidden-from-nav (stock exclusion list, unchanged, logged): account_users, access_tokens, installation_configs, app_configs, instance_statuses (still in Utilities), settings, push_diagnostics (Utilities), agent_bots, platform_apps, feature_flags JSON.
- **1b Plans & Pricing**: `PatraPlan` model + `patra_plans` table (name, nullable price decimal(12,2) — NO invented defaults, currency select USD/EUR/GBP/CAD/AUD, period monthly/yearly, nullable limits: agents/inboxes/AI replies per month, features jsonb, active, position) + `accounts.patra_plan_id` (nullable bigint + index, no FK). Custom CRUD at /super_admin/patra_plans (TAB C house style, helper text says enforcement comes later). Delete blocked while accounts are on the plan; delete behind PATRA_ADMIN_CONSOLE_ACTIONS.
- **1c Feature Gating**: /super_admin/patra_feature_gating — matrix of 48 tenant-relevant flags (deprecated + chatwoot_internal excluded) × plans; plain-English description per flag (SuperAdmin::PatraFeatureGatingHelper). patra_operator_console shown greyed + tooltip "pending fix", server-side locked too. Plan cells write patra_plans.features jsonb (audited 'plan.feature_set'). Per-account override = link to existing audited Account Control Panel toggle_feature path (no new account-flag write path). Plan assignment (accounts.patra_plan_id) audited + behind kill-switch.
- **1d Quick Actions**: Command Center panel — suspend/reactivate (account picker + reason + confirm, posts to existing gated PatraAccountsController), impersonate (user ID + reason + confirm, posts to existing PatraImpersonationsController), links to gating/plans/banner. All ≤2 clicks, all behind PATRA_ADMIN_CONSOLE_ACTIONS (buttons disabled + banner when off). "control panel" links added to Top Accounts rows.

### Files (new 10 / edited 7)
New: patra_plan.rb, patra_plans_controller.rb, patra_feature_gating_controller.rb, patra_feature_gating_helper.rb, 2 migrations, 4 plans views + 1 gating view + style partial.
Edited: routes.rb (+7 lines TAB C block), layout (+1), _navigation.html.erb (~30% — regroup), sessions/new (+4), patra_dashboard_controller (+3), patra_dashboard/show (+~60 quick actions), patra_accounts/show (color token only).

### Verify
- ruby -c: all 8 .rb files Syntax OK (verified now).
- ActionView Erubi compile: all 11 touched/new templates OK (verified now).
- Code-reviewer agent: SHIP, no blockers; should-fixes applied (kill-switch on destroy/assign_plan; dropped line-ending churn on game_health view).
- No vite build needed this phase (server-rendered ERB only).

### ⚠️ MIGRATIONS ADDED (run `rails db:migrate` on Render after deploy)
- 20260611100000_create_patra_plans.rb
- 20260611100100_add_patra_plan_to_accounts.rb

### Known/accepted
- Quick-action suspend form posts to '#' rewritten by JS onsubmit; with JS disabled it 404s (super-admin-only surface, logged).
- Google Fonts CDN on super admin pages (matches existing dashboard pattern).
