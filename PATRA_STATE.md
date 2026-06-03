# PATRA — PROJECT STATE (single source of truth for any new chat)

> READ THIS FIRST in any new chat. State back: current state, blockers, next step.

## PLATFORM STATUS
- **Railway (production):** ACTIVE — patrahq.com serving real traffic ✅
- **Render (migration):** Background Worker LIVE ✅ — Web Service needs db:chatwoot_prepare ❌
- **patra-db (Render Postgres):** Available ✅
- **patra-redis (Render Valkey):** Available ✅
- **Railway builder:** BROKEN (Metal builder bug) — support ticket open, no reply yet

## REPOS
- Production: github.com/niteshgator-netizen/patra (origin/main) → Railway
- Render staging: github.com/niteshgator-netizen/patra-clean (clean/main) → Render
- Local: C:\Users\kam work\patra
- Latest commits: 85d557e9a (both repos synced)

## RENDER SERVICES
- Web Service: srv-d8fos2mrnols73crok10 — FAILING (needs db:chatwoot_prepare after EAGER_LOAD=false deploy)
- Background Worker: srv-d8four67r5hc73abchig — LIVE ✅
- DB internal URL: postgresql://patra_db_le7e_user:cNLAKBRBYdH4fLlahtxJDUCC54fFcYbo@dpg-d8fp1dbbc2fs73btks8g-a/patra_db_le7e
- Redis internal URL: redis://red-d8fp1m99rddc73ao2gv0:6379

## KEY FIX: EAGER_LOAD
- production.rb line 11: config.eager_load = ENV.fetch('EAGER_LOAD', 'true') == 'true'
- Set EAGER_LOAD=false on Render services for cold start on empty DB
- Set back to EAGER_LOAD=true after db:chatwoot_prepare runs

## NEXT 3 STEPS
1. Finish Render Web Service: EAGER_LOAD=false → deploy → db:chatwoot_prepare → EAGER_LOAD=true → redeploy
2. Migrate Railway DB → Render DB (pg_dump → pg_restore)
3. Switch DNS patrahq.com → Render (only after Render fully verified)

## BUGS FIXED THIS SESSION (F-132 to F-136 + SideKiq)
- F-132: CSV export label_list fix
- F-133: game_actions.created_at qualified in 5 services
- F-134: bare rescue → StandardError in payment services
- F-135: Logger prefix fix
- F-136: HTTParty rescue in Telegram/Instagram handlers
- SideKiq Bug 1: tags.title → tags.name (segmentation_service.rb)
- SideKiq Bug 2: game_actions.created_at in shift_report_job.rb

## OPEN ITEMS
- ROOT BUG: orchestrator branch-order misroute (HOT FILE — needs careful fix)
- Bugs 2-8 from bug campaign
- GitGuardian 29 incidents (needs manual login)
- pgvector not installed on Render DB yet
- Render MCP: add to .cursor/mcp.json (get API key from Render dashboard)
- Telegram token in git history (redacted from README but history still has it)
- Railway support ticket pending reply

## TOOL STACK & ROUTING
- File edits/git → Cursor Pro (unlimited, most accurate)
- Browser/UI/dashboards → Claude in Chrome (8 parallel agents, 5hr limit each)
- Planning/analysis → Claude.ai Max ($100/mo)
- Complex multi-file → Claude Code (included in Max)
- Free parallel agents → Antigravity 2.0 (antigravity.google, Gemini models, free preview)
- Railway MCP: 34 tools, green in Cursor
- Render MCP: needs API key

## 8 CHROME AGENTS
1=Pink(GH Actions) 2=Blue(Render deploy) 3=Red(Secrets) 4=Yellow(Cleanup)
5=Green(DB setup) 6=Purple(Monitor) 7=Cyan(Full deploy) 8=Orange(DevOps)

## DEPLOY RULES
- git commit --no-verify (pre-commit hook broken)
- Stage files by name — never git add .
- Both Chatwoot AND SideKiq must go green = success
- Pre-deploy: bundle exec rails db:chatwoot_prepare && bundle exec rails db:migrate
- Railway internal URL: http://chatwoot.railway.internal:3000

## HOT FILES (one change per deploy, read via GitHub before touching)
- app/services/ai/reply_service.rb
- app/services/games/conversation_orchestrator.rb
- app/services/games/intent_detector.rb
- app/services/facebook/chatwoot_bridge_service.rb

## MONITORING
- BetterStack: patrahq.com UP ✅
- Heartbeat 4hr game: https://uptime.betterstack.com/api/v1/heartbeat/BZHgPuMSLcsuMFayA29HaK4m
- Heartbeat IMAP: https://uptime.betterstack.com/api/v1/heartbeat/m497AzJnPKrBdPJfJbSSKbfR
- Sentry DSN: https://91240af742cca2852f66c08a1fdd1512@o4511400274558976.ingest.us.sentry.io/4511400278228992

## STACK (unchanged)
- Backend: Ruby on Rails
- Frontend: Vue.js
- DB: PostgreSQL + PgVector
- Jobs: Redis + SideKiq
- AI: Grok 4.1 primary, Claude Opus 4.x complex, Gemini Flash OCR, DeepSeek complex replies, Voyage embeddings
- Auth: JWT in localStorage as unibox_token (legacy — do NOT rename)
- Account ID: 2, FB Inbox ID: 5
