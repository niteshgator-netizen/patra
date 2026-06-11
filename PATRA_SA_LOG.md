# PATRA SA MEGA RUN LOG

**ROLLBACK HASH (start of run):** `665b6985de6b9f71e15ab0918f805af137e1bc97`
**Branch:** `patra-feat` (worktree — never touches main patra folder)
**Date:** 2026-06-11

> ⚠️ **MIGRATIONS:** If any migrations are listed in the MIGRATIONS section below, Genius must run `rails db:migrate` on Render after deploy (Web Service shell). Check that section before deploying.

---

## RUN STATUS

| Phase | Status | Commit (= rollback point AFTER that phase) |
|---|---|---|
| 0 — Double audit | DONE | 174def1c3 |
| 1 — Super admin owner console | DONE | 89f8f6174 |
| 2 — Bug fixes | DONE | 6a8c73c42 |
| 3 — Empty state + theme cleanup | DONE | 537315936 |
| 4 — Agent feature pack | DONE | cb8bc0fac (4a) · 8b7d8bce7 (4b) · cc2c6d679 (4c) · b67d28657 (4d) · ed3abb769 (review fixes) |
| 5 — Owner analytics pack | DONE | 90663408f |
| 6 — Mockup gaps | DONE | 0f2ebb0d2 |
| 7 — Typography + de-AI polish | DONE | 8579454e0 |
| 8 — Lag profiling pass 2 | DONE | (final commit, see git log) |

Roll back a single phase: `git revert <hash>`. Roll back the whole run: `git reset --hard 665b6985d` (start hash, top of this file).

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
## PHASE 2 — BUG FIXES (root causes with evidence)

### 2a. Popover icons = empty circles
- ROOT CAUSE (best static evidence; needs visual confirm): `components-next/icon/Icon.vue` rendered icons through a child functional component (`<component :is="renderIcon" />`). Two failure modes: (1) vnode icons (the availability Online/Busy/Offline dots are `h('span', …)` vnodes from a computed — SidebarProfileMenuStatus.vue:43) were returned as SHARED vnodes without cloning → reused vnodes drop fallthrough attrs (size/color classes) → blank; (2) a propless child functional component bails out of attr-only updates, freezing classes after first render.
- FIX: Icon.vue rewritten as options-API `render()` with `inheritAttrs:false` + explicit attr merge + `cloneVNode` for vnode icons + `h(comp, attrs)` for component icons. App-wide component — reviewer-flagged update-bailout regression (spinners/unread tints) addressed by rendering in Icon's own render cycle.

### 2b. P-logo account switcher (clipped / floating pencil / instant close / errors)
- CLIPPED + "floating pencil" ROOT CAUSE (verified in source): `.pat-rail-logo` (the 40px tile that CONTAINS the switcher dropdown in collapsed mode) had `:hover { transform: scale(1.06) rotate(-3deg) }` + `transition` in TWO places — patra-themes.css:671-676 (.dark) and Sidebar.vue:951-953 (+:925, theme-agnostic, min-width:768px block). CSS transform makes the wrapper the containing block AND a trapped stacking context for the absolutely-positioned panel → panel clipped to/positioned by the tiny tile, and the compose pen-line button paints on top ("floating pencil"). BOTH rules retargeted to the trigger button (sibling of the panel — safe).
- INSTANT CLOSE + console errors ROOT CAUSE: render-time throws unmount the just-opened panel — `currentAccount.value.name` with currentAccount undefined (SidebarAccountSwitcher.vue:34,:61,:86) and `account.custom_role.name` when custom_role_id set but custom_role not serialized (:126). All guarded with optional chaining + role fallback.
- Check-mark icon could detach from its row: label div now `flex-1 min-w-0`, check icon `shrink-0 ltr:ml-auto`.
- F4 z-index family: audited — switcher/profile dropdowns z-50 inside rail z-40 is correct stacking; the REAL bug was the transform stacking-context trap above, fixed properly. No z-index inflation added.

### 2c. "Ask Patra AI" does nothing
- ROOT CAUSE (verified): PatraAiHandoffCard.vue:98-105 — handler only called `.focus()` on the composer. No API call existed behind the button.
- FIX: wired end-to-end to the EXISTING conversation-scoped backend: `PatraAiAPI.copilotSuggestion(conversationId)` (routes.rb:396 → Patra ai#copilot_suggestion → Ai::CopilotService, returns `{suggestion}`) → inserts into composer via `BUS_EVENTS.INSERT_INTO_RICH_EDITOR` (same bus event the copilot + SuggestedReplyCard use; Editor.vue:856 listens) → focuses composer. Busy state ("Asking Patra…"), empty/failure alerts via useAlert. 3 new i18n keys in en/patra.json. No new backend needed.

### 2d. Private notes
- Static trace COMPLETE, NO BREAK FOUND: toggle visible (EditorModeToggle.vue) → ReplyBox payload `private: this.isPrivate` (ReplyBox.vue:1148) → message.js sends `private` → MessageBuilder `@private = params[:private]` → DB not-null column → Message.vue renders PRIVATE variant (line 157) → `Base::SendOnChannelService#invalid_message?` (line 49) blocks private from ALL external channels incl. Facebook (bridge service unmodified, read-only check ✓ — no leak path).
- VERDICT: code path intact; most likely prior symptom = stale vite bundle. Bundle rebuilt this phase; needs runtime confirm by Genius.

### Files: Icon.vue (rewrite, 29 lines), SidebarAccountSwitcher.vue (5 small edits), Sidebar.vue (style block, 2 edits), patra-themes.css (1 rule), PatraAiHandoffCard.vue (handler + button), en/patra.json (+3 keys). public/vite/ rebuilt (pnpm exec vite build ✓ green, 36.5s, verified now).
### Reviewer: 2 blockers found (residual Sidebar.vue transform; Icon.vue functional-component update bailout) — both fixed before commit.
## PHASE 3 — INBOX EMPTY STATE + THEME TOGGLE CLEANUP

### 3a. Empty state
- EmptyStateMessage.vue rewritten: stock no-chat SVG illustrations → Patra P-mark tile (Space Grotesk, --patra gradient, 18px radius) over a STATIC radial glow (no animation, per spec). Keyboard hints (FeaturePlaceholder ⌘K / ⌘/) kept. Light + dark verified via token-scoped CSS (.dark variant for glow intensity); reviewer confirmed scoped-CSS selectors compile to correct [data-v] form.

### 3b. ONE canonical theme toggle
- NEW: Profile settings → Interface → Appearance (AppearanceSettings.vue): Light / Dark / Match-device picker + screen-dimmer slider. Canonical write path = setAppearance() in themeHelper.js (persists color_scheme, flips body.dark, syncs html[data-theme]).
- Strays handled (each logged):
  1. App.vue floating theme FAB (`#patra-theme-fab`, ☀️/🌙 emoji button) — REMOVED (markup, toggleTheme method, CSS ~88 lines, rail padding-bottom:64px reservation).
  2. App.vue floating brightness pill (`.patra-bright-ctl`, hover-revealed) — REMOVED; dimmer slider moved into Appearance section. #patra-dimmer overlay stays in App.vue, reacts to `patra:brightness` CustomEvent.
  3. Command bar (Cmd/Ctrl+K → Change appearance) — KEPT, now calls the SAME setAppearance (moved out of useAppearanceHotKeys into themeHelper; duplicate logic deleted). Not a separate toggle anymore, just a second access path.
  4. Sidebar profile menu → "Appearance" item — KEPT (opens the command bar entry above; same single mechanism).
  5. v3/components/Auth/AuthThemeToggle.vue (pre-login screens) — KEPT intentionally: no profile settings exist before login. Logged as accepted.
- BONUS FIX (found while wiring): profile settings page (.pat-page-wrap) had dark CSS var values hard-coded UNSCOPED in Index.vue scoped styles → page was dark-locked even in light theme. Vars now split .dark / body:not(.dark) with light values taken from the existing global light tokens (#F6F5F9/#FFFFFF/#1A1A24 family — no invented colors).
- i18n: PROFILE_SETTINGS.FORM.INTERFACE_SECTION.APPEARANCE.* keys added (en).

### Verify
- vite build ✓ green 39.8s (verified now); reviewer: SHIP, 2 low notes (stale picker highlight if theme changed via ⌘K while page open — accepted; LF/CRLF churn — cosmetic).
## PHASE 4 — AGENT FEATURE PACK (commits: cb8bc0fac 4a · 8b7d8bce7 4b · cc2c6d679 4c · b67d28657 4d · +review-fix commit)

### 4a. Canned responses (EXTENDED, not rebuilt)
- Already existed & verified: model + Vuex + "/" autocomplete fully wired (Editor.vue suggestion plugin trigger '/' :295 → CannedResponse.vue/MentionBox → insert), mgmt UI already Patra-restyled (pat-canned-wrap).
- ADDED: "Add sweepstakes pack" button (settings/canned/Index.vue) — seeds 8 replies sequentially through the EXISTING createCannedResponse action (each save fires the Bella RAG embed hook — untouched). Texts are 1-2 line human cashier voice; ALL business facts are [bracketed] placeholders (payment methods/handles/freeplay rules) — nothing invented. Per-account, fully editable, skips existing short_codes, per-item failure tolerant (review fix).

### 4b. Collision detection (extends existing presence/typing infra, ~140 lines)
- Backend mirror of typing: CONVERSATION_VIEWING_ON/OFF events (lib/events/types.rb), Conversations::ViewingStatusManager, POST toggle_viewing_status (conversations member route), ActionCableListener#conversation_viewing_on/off using existing typing fan-out. Wisper delivery verified (method_name mapping + SyncDispatcher subscription).
- Frontend: conversationViewingStatus store module (150s stale-timer kills ghost entries), actionCable handlers, ConversationHeader announces on open/switch/close + re-announces every 60s, amber "X is viewing" chip in conversation header, amber eye pip on conversation list card avatar (ConversationCard.vue). i18n VIEWING_ONE/VIEWING_MANY.

### 4c. SLA timers — Phase 0 audit was WRONG: SLA EXISTS in this fork
- Correction to 0b gap table: enterprise/ folder loads (ChatwootApp.enterprise? true), SlaPolicy + AppliedSla models, sla_policies REST routes (routes.rb:145), automations `add_sla` action (enterprise action_service), FULL frontend (store, API, settings page already pat-page-wrap styled, SLACardLabel chips in list + header), AND a Patra cron job Sla::CheckViolationsJob runs EVERY MINUTE (schedule.yml:99) sending Telegram breach alerts via Audit::TelegramNotifier.sla_violation. No SLA models were built — nothing needed building.
- ENABLE: flip the `sla` feature flag per account — Feature Gating page (Phase 1c) or Account Control Panel. Until then the settings page shows the paywall card.
- ADDED: green→amber→red countdown (both SLACardLabel components): teal while >half the first-response window remains, amber past halfway, ruby on miss (review fix: color computed now re-evaluates on the 60s tick). Per-inbox config hint (SLA.PER_INBOX_HINT) — done via existing Automations (inbox condition → Add SLA action); de-AI'd the stock SLA description copy.

### 4d. Auto-routing (surfaced — already built in fork)
- assignment_v2 flag is ON; AssignmentPolicy (round_robin, earliest_created/longest_waiting, fair_distribution limit+window) + full REST + inbox attach/detach ALL exist. UI exists & reachable: Inbox settings → Collaborators (toggle + policy card + create/link) and Settings → assignment policy pages (sidebar route confirmed Sidebar.vue:563-571).
- FIXED: assignmentPolicy/Index.vue was dark-locked (same unscoped CSS-var bug as profile settings) — vars now theme-scoped, light mode works.
- PROPOSED (logged, not built): (1) Agent capacity policies — Vue scaffolding exists, NO backend model/API (est: 1 migration + model + CRUD controller + assignment-service check, ~1-2 days). (2) By-intent routing — CONFIRMED intent is written by the orchestrator AFTER assignment (additional_attributes['pending_load_intent'], post-routing; conversation_builder has no intent at create). Routing by intent needs intent-at-create or a reassignment step = Rules Engine lane, NOT touched.

### Verify
- ruby -c all 5 changed .rb ✓; vite build ✓ green ×3; reviewer (full phase diff): SHIP, 0 blockers, 2 should-fixes applied (SLA color reactivity, pack seeding per-item failure), comment nit fixed.
- Runtime verify for Genius: open same conversation in two browsers → amber "is viewing" chip in header + eye pip in list within ~1s; close one tab → chip clears (≤2.5 min worst case via stale timer).
## PHASE 5 — OWNER ANALYTICS PACK

### 5a. CSAT (verified existing + extended)
- VERIFIED existing & branded: inbox settings CSAT page (Patra-styled, emoji/star display types, survey rules), PUBLIC survey page already Patra purple (survey/views/Response.vue:214-251 — #6e56cf gradient), CSAT reports page at /reports/csat with agent/inbox/team/rating filters + CSV download.
- ADDED per-agent CSAT score: Analytics::AgentPerformanceService now returns csat_score (avg 1-5 rating grouped by CsatSurveyResponse.assigned_agent_id, one query) — surfaces on Leaderboard + Patra overview agent table.
- Enable: per-inbox toggle in inbox settings (already shipped). No code needed.

### 5b. Analytics dashboard (extended existing /patra/reports page — NOT rebuilt)
- VERIFIED existing: PatraReports.vue page + rich endpoint (today/this_week KPIs incl. ai_handle_rate = AI-vs-human marker [resolved conversations with no human outgoing message; human = sender_type 'User'], payment volume 7d from GameAction read-only, revenue by game 30d, conversation volume, busiest-hours heatmap). Charts are CSS-bar/heatmap based (no chart lib needed; Chart.js available but unused here — existing pattern kept).
- FIXED: agent table read `agent.messages` — field NEVER sent by the service (always blank). Now shows Handled / First response / CSAT with correct service field names.
- FIXED: page was dark-locked (same unscoped CSS-var bug) — theme-split applied.
- No "needs tracking" cards required — every spec metric had a real data source.

### 5c. Agent leaderboard (extended existing Leaderboard.vue)
- BUG FIX: rankings read `agent.resolved || agent.messages_today` — neither field exists in AgentPerformanceService output → every agent showed 0 forever. Fields aligned (conversations_handled, avg_first_response_minutes).
- ADDED: time-range picker (Today / 7 days / 30 days → ?agent_period= on the existing endpoint), CSAT column (5a), Loads column (GameAction read-only, attributed via conversation assignee — GameAction has no executed-by column; caveat shown), Loads KPI. Podium styling kept (mockup-matched, both themes via tokens).

### 5d. Sweepstakes report (new page on existing machinery, read-only)
- Backend: reports#sweeps (same admin-only ReportPolicy) — totals (loads/cashouts/net + freeplay vs paid via the canonical metadata->>'freeplay' marker used by 8+ existing services), by_game (agent_game→game join), by_agent (conversation-assignee attribution, labeled), by_day. JSON + CSV (CSVSafe template, same pattern as api/v2 reports). Route: GET patra/reports/sweeps(.csv)?period=day|week.
- MONEY-SAFETY: reviewer-verified every query is count/sum/average/pluck — zero write paths.
- Frontend: SweepsReport.vue at /patra/sweeps (admin-only route + role-gated sidebar entry "Sweeps Report"), day/week toggle, KPI cards, 3 tables, Export CSV button.

### Verify
- ruby -c ×3 ✓, patra.json parses ✓, vite build ✓ green; reviewer: SHIP (money-safety pass, injection pass, enum/assoc/i18n all verified). LOW items fixed (admin gate on sidebar entry, falsy-zero render). Genius: test the CSV download link once on staging (plain-link auth assumed from the existing export_url pattern).
- Pre-existing INFO (not a regression, logged): /patra/leaderboard route allows agents but its API is admin-only → agents see an empty board.
## PHASE 6 — MOCKUP GAPS

### 6a. Knowledge Base — VERIFIED, one fix
- TWO KB surfaces exist and work: (1) Patra internal KB at /patra/knowledge (KnowledgeBase.vue, 316 lines, Patra-styled) with WIRED search — KnowledgeArticlesAPI.search → GET knowledge_articles/search → knowledge_articles_controller#search (routes.rb:510, controller :30). Search endpoint exists, so per spec the search is wired (keyword search; no new RAG work — Rules Engine lane). (2) Chatwoot Help Center portals (article editor, categories, locales, settings pages all present under helpcenter/, behind help_center flag, Patra tokens in components per Phase 0 recon).
- FIX: the Help Center portal had NO sidebar entry (URL-only) — added "Help Center" to the More group (portals_index). Patra KB entry kept separate ("Knowledge Base").

### 6b. Connect Facebook — VERIFIED, nothing to build
- Guided connect screen ALREADY exists and is Patra-branded: inbox creation → Facebook channel (channels/Facebook.vue) shows pat-connect-card (f tile, title, description, "Continue with Facebook" CTA, security note, help text) before login starts; credentials flow = existing backend (facebook_connect controller + meta_app endpoints under patra namespace). No edits made.

### 6c. Remaining Phase 0b gap-table sweep
- Canned responses → DONE 4a. CSAT → DONE 5a. Help Center → DONE 6a. Auto-assignment → DONE 4d. Reports → DONE 5b-5d. SLA → DONE 4c (audit corrected: existed all along). Typing/presence → DONE 4b. Theme toggles → DONE 3b.
- PROPOSED (carried, with estimates): (1) Agent capacity policies backend — model+migration+CRUD+assignment check, ~1-2 days. (2) By-intent routing — needs intent at conversation-create or post-assignment reassignment; Rules Engine lane, est. unknown until that lane lands. (3) Billing/patra_billing_subscriptions — Command Center panel auto-activates when the table ships (Phase 1 noted).
## PHASE 7 — TYPOGRAPHY + DE-AI POLISH

### 7a. Font sweep
- All 13 sub-11px font sizes in patra-themes.css (status pills, vip-badge 9px, role badges, tags, char count, donut labels, message metadata — all 9-10px) raised to 11px. Same in ConversationHeader.vue (participants/auto-reply chips, 9-10px → 11px), PatraAiHandoffCard.vue (section titles 10px → 11px), PatraAiTraining.vue, PatraOwnerDashboard.vue, PatraReports.vue.
- NOT raised to 12px: these are pill/badge micro-labels — at 12px the pills overflow their fixed-height rows (layout does NOT allow; spec's "where layout allows" clause applied). Body text was already ≥12px everywhere checked.

### 7b. De-AI / microcopy pass (every string changed, before → after)
1. CONVERSATION.SELECT_A_CONVERSATION: "Please select a conversation from left pane" → "Pick a conversation on the left to get started"
2. CONVERSATION.NO_MESSAGE_1: "Uh oh! Looks like there are no messages from customers in your inbox." → "All quiet — no customer messages yet. New ones land here the moment they arrive."
3. CONVERSATION.NO_INBOX_1: "Hola! Looks like you haven't added any inboxes yet." → "You haven't connected an inbox yet."
4. CONVERSATION.NO_INBOX_AGENT: "Uh Oh! Looks like you are not part of any inbox. Please contact your administrator" → "You're not in any inbox yet — ask your admin to add you."
5. CANNED_MGMT.LIST.404: "There are no canned responses available in this account." → "No saved replies yet — add one, or load the sweepstakes pack below."
6. (earlier phases, same pass:) super admin login "Howdy, admin 👋" → "Patra Owner Console" (P1); SLA.DESCRIPTION corporate boilerplate → plain Patra voice + PER_INBOX_HINT (P4c); Leaderboard subtitle (P5c).
- Stock illustrations: inbox no-chat SVGs replaced with Patra P-mark (Phase 3a). Other stock Chatwoot strings auto-rebrand at runtime via INSTALLATION_NAME replacement (useBranding) — left alone by design.

### 7c. Dead buttons / disabled features found during the sweep
- FIXED in earlier phases (all were genuinely dead): "Ask Patra AI" (no API call — 2c), Leaderboard rankings (read non-existent fields, always 0 — 5c), Patra overview agent table (same — 5b), Help Center portal (no nav entry, URL-only — 6a).
- INTENTIONALLY disabled, tabled: patra_operator_console flag toggle (greyed "pending fix" — Phase 1c); brightness pill removed by design (3b). No other dead controls found statically.
## PHASE 8 — LAG PROFILING PASS 2 (evidence-first; P1/P2 shipped)

### Audit findings (with evidence)
(a) INFINITE ANIMATIONS + FILTERS: 9 infinite animations in patra-themes.css. Cheap (opacity/transform only — compositor): pip, slaPulse, sparkPulse, patraFloat ×3, patraSpinGlow (rotate), skeleton sweep (loading only). EXPENSIVE: `.patra-mesh-bg::before/::after` — two ~700px always-animating layers with `filter: blur(100px)` (lines 271-300). NOTE found while auditing: the mesh drift `@keyframes meshA` (transform, line 303) is SHADOWED by a later redefinition (opacity-only, line 535) — the mesh accidentally runs the cheap opacity fade instead of its intended transform drift. LEFT ALONE DELIBERATELY (fixing the name collision would make it more expensive).
(b) NON-COALESCED DOCUMENT LISTENERS: Dashboard.vue:84 had a SECOND global spotlight (#patra-global-spotlight) with the exact pre-P1 pattern — uncapped document mousemove writing left/top (layout-triggering) on a 460px blurred fixed layer, on EVERY pointer move app-wide. This was the single biggest remaining lag source found. 24 document/window listeners total; the rest are balanced add/remove or once-only.
(c) LAYOUT THRASH: per-event getBoundingClientRect + style writes in 7 mousemove hot paths: ConversationCard.vue (every list-card hover — hottest), GameCard.vue, ContactProfileStats.vue, canned Index.vue (spotlight + card glow), Dashboard.vue (global spotlight), PatraOwnerDashboard.vue (spotlight + 2 closest()+rect reads per event + extra per-card listeners), PatraAiTraining.vue (same).
(d) VIRTUALIZATION: conversation list already uses a virtual list (ConversationList.vue virtualListRef) — no work needed.

### Fixes shipped (motion language kept everywhere)
1. All 7 mousemove hot paths rAF-coalesced (≤1 layout read + write batch per frame, was uncapped per event). Spotlights now move via compositor-only translate3d (was left/top), with `left:0; top:0; will-change:transform` anchors (reviewer-caught requirement, matching the P1 App.vue pattern) and pending-frame cancellation on mouseleave (no stuck-lit spotlight).
2. Per-card duplicate listeners in PatraOwnerDashboard/PatraAiTraining folded into the single coalesced root handler via closest() unions (selector coverage reviewer-verified).
3. Mesh blur 100px → 64px (patra-themes.css + canned Index.vue) — blur cost ∝ radius × area; look preserved.

### PROPOSED (visual-risky, not done — file:line)
- backdrop-blur-[100px] on popovers/menus/date-picker (12 spots: DropdownBody.vue:29, DropdownMenu.vue:139, Popover.vue:111/129, ResolveAction.vue:224, DatePicker.vue:373, SLAPopoverCard.vue:44, contextMenu/Index.vue:284, menuItemWithSubmenu.vue:43/53, ConversationBasicFilter.vue:150, components-next equivalents) → reduce to backdrop-blur-2xl (40px). Transient surfaces, cost only while open; visual frosted-glass signature changes slightly — Genius should eyeball one popover before a blanket change. Est: 30 min.
- patraSpinGlow rotating conic ::before on ai-handoff-card (dark mode, 8s infinite) — one permanently-composited rotating layer; fine for one card, kill if cards multiply.

### Verify
- vite build ✓ green (twice — after fixes too). Reviewer verdict on first pass: DO NOT SHIP (missing spotlight anchors + rAF/mouseleave race + unused import) — ALL FIXED, rebuilt, re-verified compile.
- Runtime check for Genius: cursor spotlight must track the cursor exactly on: canned responses page, owner dashboard, AI training page, main dashboard. If any spotlight sits offset from the cursor, report back (anchor fix regression test).

---

# FINAL DUMP

## ⚠️ DEPLOY CHECKLIST FOR GENIUS (read before deploying)
1. **MIGRATIONS — must run `rails db:migrate` on Render after deploy (Web Service shell):**
   - 20260611100000_create_patra_plans.rb (new patra_plans table)
   - 20260611100100_add_patra_plan_to_accounts.rb (nullable accounts.patra_plan_id + index)
2. public/vite/ bundles are BUILT and COMMITTED (final build green, 37s). No local build needed.
3. To turn on SLA for account 2: Feature Gating page or Account Control Panel → toggle `sla` (needs PATRA_ADMIN_CONSOLE_ACTIONS=true for the account-toggle path).
4. Quick actions / impersonation / plan-delete / plan-assign all sit behind PATRA_ADMIN_CONSOLE_ACTIONS (unchanged kill-switch).
5. This branch (patra-feat worktree) is COMMITTED, NEVER PUSHED — per instructions. 13 commits total on top of 665b6985d.

## Runtime verifications Genius should do (can't be proven statically)
- 2a: avatar popover icons render (both themes). 2b: P-logo switcher opens un-clipped, stays open, no console errors. 2c: "Ask Patra AI" inserts a suggested reply into the composer. 2d: private note send → yellow note, NOT delivered to FB.
- 4b: two browsers, same conversation → "is viewing" chip + amber list pip. 4a: canned page → "Add sweepstakes pack" creates 8 editable replies (then edit the [bracketed] bits!).
- 5d: Sweeps Report page + CSV download (auth via plain link assumed from existing export pattern — verify once).
- 8: spotlights track cursor exactly on all four pages listed above.

## Open items / PROPOSED (consolidated)
1. Agent capacity policies backend (UI scaffolding exists) — est 1-2 days.
2. By-intent routing — blocked on intent-at-create; Rules Engine lane.
3. Popover backdrop-blur reduction (file list above) — est 30 min + visual sign-off.
4. Billing tables (patra_billing_subscriptions) — Command Center panel auto-activates when shipped.
5. Leaderboard route is agent-visible but its API is admin-only (pre-existing) — decide: open the API to agents or hide the nav item for agents.
6. AppearanceSettings picker highlight can go stale if theme changed via ⌘K while the page is open (accepted, logged Phase 3).

STOP. Run complete — committed on patra-feat, never pushed.
