# PATRA AGENT-POLICY SETTINGS UI — LANE B LOG (it6, prefix `policy-ui:`)

> **DESIGN PREVIEW (Genius approval gate):** open `tmp/agent_policy_preview.html` in a browser — a
> standalone static mock of the finished screen: all 3 sections, the bonus modal (time-window day-picker),
> empty + filled states, LIGHT and DARK (toggle button top-right).
>
> Run-start rollback (whole it6 run incl. policy-ui): `git reset --hard 7b2f10f6f6b2cc70600af3b454cbdc9f0e66a1ae`.
> NEVER pushed. Bound to the REAL Lane-A model (GATE-1 record in PATRA_BULLETPROOF_LOG.md).

## BINDING TO LANE-A REALITY (the decisive design call)
The policy lives at `account.settings['agent_policy']` (store_accessor on Account), validated server-side on
every save by `JsonSchemaValidator` against `AccountSettingsSchema::AGENT_POLICY_SCHEMA`. So:
- **NO dedicated REST controller** (would be a fake — there is no agent_policies table). B1 = a ONE-LINE
  strong-params addition to the existing, admin-only account update.
- **NO fake api/agentPolicy.js** — the store action composes the REAL `accounts/update` path (api/account.js).
This is the honest binding; inventing a parallel endpoint would diverge from the actual persistence.

## B0 — TEMPLATES + STACK (verified by parallel explorers)
Vue 3 · Vuex (namespaced) · `<script setup>` lists · Options/`<script setup>` modals · `useAlert()` ·
`Button` from `dashboard/components-next/button/Button.vue` (NextButton — the real button component; there is
NO `woot-button`) · `woot-modal-header` + `Modal.vue` (UIKit) · Tailwind with `dark:` variants + the `woot`
purple palette. Templates mirrored: canned/{Index,AddCanned}.vue + integrations/Games.vue + GameConfigModal.

## B1 — BACKEND (app/controllers/api/v1/accounts_controller.rb; +1 permitted key)
`permitted_settings_attributes` += `{ agent_policy: {} }` (permit the whole nested subtree). Safety: the
JSON-schema validator rejects a malformed policy (422); admin-only via `account_policy#update?`
(before_action :check_authorization). ruby -c clean. VERIFIED: explorer confirmed accounts#update merges
`settings_params` into `@account.settings` then `save!` (validator runs).

## B2 — PLUMBING (store/modules/agentPolicy.js, registered in store/index.js)
Thin namespaced module: getter `getAgentPolicyUIFlags`, action `updateAgentPolicy(policy)` →
`dispatch('accounts/update', { agent_policy: policy }, { root: true })` (the real, validated path) +
isUpdating uiFlag. READ is via `useAccount().currentAccount.settings.agent_policy`. (No api/agentPolicy.js —
see binding note.)

## B3 — THE SCREEN (routes/dashboard/settings/agentPolicy/Index.vue + AgentBonusModal.vue)
Three sections, RESPONSIVE from the first line (root `h-full min-h-0 overflow-y-auto` owns its scroll — the
Lane-C lesson; `grid-cols-1 md:grid-cols-2`, `grid-cols-2 lg:grid-cols-4`, stacks ≤768px), light+dark via
Tailwind `dark:`:
- **Bonuses**: LIST of cards (name, %, kind, min/cap, schedule summary, On/Off pill) + Add/Edit/Delete;
  empty state "No bonuses yet — add your first". Modal (AgentBonusModal): name (free-text), kind, percent,
  min/max deposit, cap, schedule toggle Always vs Time-window → 7-day picker + start/end time, active toggle.
- **Referral**: percent, trigger_deposit_number, cap, active toggle.
- **Cashout**: min, max, playthrough min/max, per-platform add-rows, terms text, active toggle.
- **Client validation**: percent 0–100, amounts ≥0, window end>start; first error → toast, save aborted.
- Save → `agentPolicy/updateAgentPolicy` → success/error toast (useAlert).

## B4 — ROUTE + MENU (admin/owner gated, mirrors Games)
agentPolicy/agentPolicy.routes.js (`settings_agent_policy_index`, `meta.permissions: ['administrator']`,
SettingsWrapper) → registered in settings.routes.js. Sidebar.vue Settings group: "Agent Policy"
(`i-lucide-shield-check`) next to Game Rules, same admin gating. i18n agentPolicy.json (60 keys) registered
in i18n/locale/en/index.js.

## CONVENTION-AUDITOR (general-purpose agent, grepped real component APIs)
- **BUILD/RENDER FIX (caught + fixed):** the screen used `<woot-button>` — NOT a registered component (it
  does not exist in this repo). Replaced all 9 with the real `<Button>` (NextButton) + corrected prop VALUES
  (`size sm`, `variant ghost`, `color="ruby"` not color-scheme/alert, `icon="i-lucide-plus/pencil/x"` not
  add/edit/dismiss). Re-verified: 0 residual woot-button, Button imported in both, no stray invalid props.
- VERIFIED CORRECT: i18n 100% (60 keys used = 60 defined, incl. SIDEBAR NAV_LABEL; zero missing/dead);
  store namespaced + accounts/update accepts {agent_policy}; route + SettingsWrapper + frontendURL resolve
  like canned; permission gating matches Games; `woot`/`slate`/`green` Tailwind shades all exist; imports
  (useStore/useAccount/useAlert/Modal) resolve; `<script setup>` clean. Nits (cosmetic, not fixed):
  accounts/update double-wraps Error → toast shows "Error: …" prefix; Modal `:on-close` deprecated (matches
  canned's existing usage).

## KEYS-vs-LANE-A REALITY (UI writes EXACTLY the resolver's shape)
UI persists `account.settings['agent_policy'] = { bonuses:[{id,name,kind,percent,min_deposit,max_deposit,
cap,schedule:{mode,days,start_hm,end_hm},active}], referral:{percent,trigger_deposit_number,cap,active},
cashout:{min,max,playthrough_min,playthrough_max,per_platform,terms_text,active} }` — byte-for-byte what
`Games::PolicyResolver` reads + what `AGENT_POLICY_SCHEMA` validates. Day index 0=Sun..6=Sat matches the
resolver. Empty/inactive ⇒ Bella defers (Lane A).

## OWNER MUST FILL (no defaults; empty ⇒ defer/GameRule fallback)
bonuses[].{name, percent, min_deposit, schedule (+days/start/end if window), active} · referral.{percent,
trigger_deposit_number, active} · cashout.{min, max, playthrough_min/max, active}.

## VERIFICATION STATUS
- verified-in-code: B1 ruby -c; SFC balance (script/style/template) on both Vue files; JSON valid; i18n keys
  complete; store/route/sidebar registrations present; button APIs corrected per auditor.
- prod-only / cannot-physically-click (Genius tests in browser): the rendered screen, save round-trip to
  account.settings, admin-only gating in the live app, light/dark visuals, mobile stacking. The single vite
  build at FINALIZE compiles the bundles (the definitive compile check).
