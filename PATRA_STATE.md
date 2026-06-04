# PATRA — PROJECT STATE (single source of truth for any new chat)

> READ THIS FIRST in any new chat. State back: current state, blockers, next step.

## PLATFORM
- Production: Render (migrated June 3 2026 — Railway RETIRED)
- patrahq.com → 216.24.57.1 (Render), SSL active, DNS 100% propagated
- Repos: patra (origin/main) + patra-clean (clean/main, Render auto-deploy)
- Local: C:\Users\kam work\patra
- Deploy = git push → auto-deploys Render (both repos)
- Pre-deploy command = EMPTY on both services

## RENDER SERVICES
- Web Service: srv-d8fos2mrnols73crok10 (Standard 2GB $25/mo) ✅
- Background Worker: srv-d8four67r5hc73abchig (Standard 2GB $25/mo) ✅
- patra-db: Basic 5GB (user=patradb_13m1_user, rotated June 3) ✅
- patra-redis: Starter 256MB $10/mo ✅
- Total: ~$57.50/mo

## STACK
- Backend: Ruby on Rails + Vue.js + PostgreSQL + PgVector + Redis + SideKiq
- AI: Grok 4.1 primary, Gemini Flash OCR, DeepSeek replies, Voyage embeddings
- Auth: JWT in localStorage as unibox_token (legacy — do NOT rename)
- Account ID: 2, FB Inbox 5 (Channel::Api, working via Zernio)

## BUGS STATUS (June 3)
- Bug 1 ✅ chosen_game_slug helper
- Bugs 2/3/4 ✅ intent branch order + guards (1e9e4a33a)
- Bug 5 ✅ PayPal/CashApp OCR (8849811a3)
- Bug 6 ✅ already fixed
- Bug 7 ✅ handle format duplication (2233a28b5)
- Bug 8B ✅ image rendering Vue (ed329cdbf)
- Bug 8A ❌ OPEN — FB bridge download failure (chatwoot_bridge_service.rb hot file)

## RAG INTENT TRAINING
- Task: bella:mine_intents PROVIDER=deepseek DEEPSEEK_MODEL=deepseek-chat BATCH=25
- Status: 11,148/64,445 labeled (needs restart after DB rotation)
- Top intents: load_deposit(3265), payment_handle_request(1593), load_freeplay(1451)
- Cost: ~$4 total on DeepSeek ($7.26 balance)
- Restart command (Web Service Shell):
  nohup bundle exec rake bella:mine_intents PROVIDER=deepseek DEEPSEEK_MODEL=deepseek-chat BATCH=25 > /tmp/mine_intents.log 2>&1 &

## OPEN ITEMS
- Bug 8 Problem A (FB bridge hot file — one deploy)
- RAG intent training → wire into orchestrator after training finishes
- Juwa silent-fail (check_balance verification net)
- Telegram bot token rotation (do via @BotFather manually)
- Account name "patra" → "Patra" (Settings → General)
- Cloudinary permanent image storage (FB URLs expire ~30d)
- Auto-failover (record_failure! not auto-wired)

## SECURITY
- DB credentials rotated June 3 (new user: patradb_13m1_user)
- Gemfile.lock fixed permanently (3a40e3448, BUNDLE_FROZEN removed)
- IMAP_ENABLED=false (crash loop fixed)
- 30 Dependabot vulns fixed (vitest/axios/js-cookie)
- Gems pinned: jwt 3.2.0, net-imap 0.6.4, nokogiri 1.19.3
- Telegram token still needs @BotFather rotation

## HOT FILES (one change per deploy, read via GitHub before touching)
- app/services/ai/reply_service.rb
- app/services/games/conversation_orchestrator.rb
- app/services/games/intent_detector.rb
- app/services/facebook/chatwoot_bridge_service.rb

## DEPLOY RULES
- git commit --no-verify (pre-commit hook broken)
- Stage files by name — never git add .
- Both Web Service AND Background Worker must go green
- git push origin main + git push clean main

## MONITORING
- BetterStack: patrahq.com ✅, Patra Login Health ✅, Patra Render(production) ✅
- Heartbeats: Patra IMAP Check ✅, Patra Game Refresh (4hr) — recovers next cycle
- Sentry DSN configured on Render

## KEY DESIGN TOKENS (dark Patra)
--canvas:#050409 --surface:#0C0B12 --patra:#6E56CF --patra-2:#8B5CF6
--text:#EDEDF2 --text-2:#A8A6B6 --green:#3FB950 --red:#F85149
Fonts: Space Grotesk (display), Inter (body), JetBrains Mono (mono)

---
*Last updated: June 3 2026 — Render migration complete, Bugs 1-8 fixed, RAG training running*
