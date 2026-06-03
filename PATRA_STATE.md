# PATRA — LIVE STATE

> Read by Claude + Cursor at every session start. Keep under 5KB. Update at end of every chat.

## STATUS (as of 2026-06-02)
- **Migrating to Render — Web Service build in progress**
- Last green deploy: e3b4ad31d — Fix: ConversationView shell dark theme — 2026-05-31
- Launch readiness: In progress

## LAST DEPLOY
- **Railway ACTIVE — serving production traffic**

## CURRENT BLOCKER
**Render Web Service — GitHub Actions building assets**
- File: .github/workflows/
- Plan: Wait for GitHub Actions to finish building assets, then confirm Render deploy is green
- Owned by: Ops/Setup

## ACTIVE PARALLEL CHATS
| Chat | Doing | Files it owns |
|---|---|---|
| Ops/Setup (this) | Render migration — infra setup, DNS, DB migration | .cursorrules, BUGS_*.md, PATRA_STATE.md, CLAUDE.md |
| Bug fixes | Monitoring Railway production bugs | conversation_orchestrator.rb |
| UI/dark theme | Dark theme polish on Vue components | Vue files, CSS |
| RAG mining | Building bella RAG pairs for AI context | bella_rag_pairs |

## NEXT 3 STEPS
1. Confirm Render Web Service deploys green
2. Migrate real data from Railway DB to Render DB
3. Switch DNS from Railway to Render

## DO NOT TOUCH
- Railway production environment until Render is confirmed green
- DNS until Render Web Service is confirmed stable

## CHAT LOG (newest on top)
2026-06-02 — Ops/Setup — Render migration in progress: Web Service + Worker + Postgres + Redis created on Render. GitHub Actions asset pre-builder added. Awaiting green deploy.
2026-05-31 — Ops/Setup — Shipped .cursorrules, BUGS_FIXED.md, BUGS_OPEN.md, PATRA_STATE.md, CLAUDE.md. Tag system locked.
