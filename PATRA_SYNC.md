# PATRA SYNC — SHARED HANDOFF (read at start of every session)

Shared notebook between planning Claude (chat) and Claude Code (terminal). Both read this first.
Multiple work streams run in parallel (UI, RAG, backend). This file prevents them colliding.

## DEPLOY DISCIPLINE WITH PARALLEL STREAMS
- Different files = safe in parallel. Same file = sequential, never two streams editing one file.
- ONE stream deploys at a time. After a stream commits, the next stream runs git fetch origin && git rebase origin/main before its own deploy.
- Never deploy two streams in one commit — if it breaks you won't know which stream caused it.

## CURRENT STATE
- Last updated: 2026-06-07
- Deploy: Render GREEN. Last big deploy = CSS visual overhaul, 6 commits, 8/8 Chrome QA pass.
- Streams active: A=UI (css/vue files), B=RAG+backend (rb files)

## DONE (do not redo)
CSS overhaul shipped: patra-themes.css (40 corrected vars + light mode + bubble gradients), App.vue (spotlight z-index), commandbar.vue (palette purple), ConversationCard.vue (cursor glow), PatraOwnerDashboard.vue (KPI glow), Sidebar.vue (light mode vars).

## OPEN ITEMS
- Light-mode toggle flicker (center pane stays dark until reload) — minor
- Manage / Community Support buttons → remove or repoint to patrahq.com — NEEDS VERIFY (not confirmed live)
- Online dot on conversation cards not showing
- RAG_TO_INTENT_MAP covers 16 of 27 intent labels
- bella_rag_pairs account_id state — verify with /ragcheck
- ROTATE ALL secrets at launch (GitGuardian 29 + Telegram + GitHub PAT + DB URL) — deferred
- super_admin 500 — crash in _navigation.html.erb resources loop lines 40-46, needs exact exception to debug

## DO NOT DO
- Do NOT revert patra-themes.css colors. Live values #050409 canvas + #6E56CF purple are CORRECT. Old values #0f0f13, #7c6ff7, "15 15 19" are WRONG — never restore.
- Do NOT accept bulk "do all N things, don't ask questions" tasks. One focused batch, show diffs, hand off.

## STREAM A (UI) — last action
Fixed stale branding — INSTALLATION_NAME DB value changed Chatwoot→Patra via Render Shell, cache cleared, tab now shows Patra. No code/deploy needed.

## STREAM B (RAG/backend) — last action
[fill in]
