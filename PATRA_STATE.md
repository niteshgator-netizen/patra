# PATRA — LIVE STATE

> Read by Claude + Cursor at every session start. Keep under 5KB. Update at end of every chat.

## STATUS (as of 2026-06-03)
- **Overnight bug-fix session shipped** — ROOT intent misroute fixed; safe fixes + RAG rake hardened
- **Render migration in progress** — DB connection fix deploying

## LAST DEPLOY
- Last green deploy: e3b4ad31d — Fix: ConversationView shell dark theme — 2026-05-31
- Pending push: intent_detector branch order + export N+1 + rake fixes (this session)

## RAILWAY STATUS
- **ACTIVE** — serving production
- SideKiq bugs fixed: `tags.title` → `name`, `game_actions.created_at` qualified

## RENDER STATUS
- **Build GREEN**
- Runtime was failing (`PG::ConnectionBad` to Railway IP)
- `DATABASE_URL` updated to Render internal DB

## CURRENT BLOCKER
**Render web service boot** — confirm green after `DATABASE_URL` fix; then `db:migrate` + pgvector

## OPEN
- GitGuardian 29 secrets
- Railway builder broken
- Patra dashboard TODOs (wire backend KPIs) — not code bugs

## RESOLVED THIS SESSION
- **ROOT BUG:** `IntentDetector.detect` ran `payment_method_chosen` before load/cashout; "Cash Machine" / `cash` alias misroutes fixed
- Export CSV N+1 on `messages.count`
- `bella:mine_intents` rake JSON + bucket summary
- Vue `console.log` removed (NotificationPreferences, YearInReviewModal)
- IMAP check job duplicate handle query

## ACTIVE PARALLEL CHATS
| Chat | Doing | Files it owns |
|---|---|---|
| Ops/Setup (this) | Overnight fixes + Render migration | BUGS_*.md, PATRA_STATE.md, intent_detector.rb |
| UI/dark theme | Dark theme polish on Vue components | Vue files, CSS |
| RAG mining | Run `bella:mine_intents` after deploy | bella_rag_pairs |

## NEXT 3 STEPS
1. Deploy pushed commits — verify "load on cash machine" routes to `:load` not payment pick
2. Confirm Render web service boots → `db:migrate` → pgvector
3. Run `LIMIT=50 bundle exec rake bella:mine_intents` smoke test on Render/SideKiq

## DO NOT TOUCH
- Railway production env until Render confirmed green
- DNS until Render Web Service stable
- Hot files in same commit as bulk fixes (orchestrator untouched this session)

## CHAT LOG (newest on top)
2026-06-03 — Overnight session — Fixed ROOT intent branch order in IntentDetector (game before payment); export N+1; rake mine_intents; Vue console.log cleanup; IMAP job query dedup. Game API clients already had timeout+rescue — no change.
2026-06-03 — Ops/Setup — Render DB URL fix deploying; Railway SideKiq fixes shipped.
2026-06-02 — Ops/Setup — Render migration in progress.
2026-05-31 — Ops/Setup — Shipped .cursorrules, BUGS_FIXED.md, BUGS_OPEN.md, PATRA_STATE.md.
