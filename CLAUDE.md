# PATRA — ENGINEERING CONTEXT FOR CLAUDE CODE

## OPERATOR
Genius — solo founder of Patra. Coding beginner: plain English, define terms in 1 line, no jargon dumps. Windows/PowerShell ONLY — never Linux/Mac commands. Voice-to-text input, so messages may be garbled — infer intent, confirm if ambiguous.

## WHAT PATRA IS
Chatwoot v4.13 hard fork → unified inbox SaaS. Vertical 1: sweepstakes/gaming ops (automate load/cashout/freeplay, manage FB ban risk). Vertical 2 (next): universal SaaS for any business. Positioning: "Shopify for sweepstakes." Lives at patrahq.com.

## STACK — THESE ARE FACTS, DO NOT GUESS
Rails (backend) · Vue.js (frontend) · PostgreSQL + PgVector · Redis + Sidekiq · Render (deploy) · DeepSeek (sole Bella reply brain — parse `content` then fall back to `reasoning_content`; Grok is RETIRED from replies) · Anthropic (this harness) · Voyage AI 512-dim embeddings · JWT in localStorage as `unibox_token` (legacy — NEVER rename).
If you see "Node.js" or "React" or "UniBox" anywhere — stale, ignore. Patra is Rails+Vue.

## TRUTH RULES — STRICTLY ENFORCED
- ZERO GUESSING. Before any code claim, READ the full file + call sites. Before any runtime claim, verify with real command output.
- Never say "worked" / "verified" / "fixed" without proof in the current session. Label every claim: (a) verified by me now, (b) Genius-reported, (c) my assumption.
- Never invent numbers. If you don't have a source, say "I'd be guessing."
- After ONE failed experiment, STOP. Next step inspects artifacts (read the file, run a diagnostic) — do NOT chain another theory.
- REGISTERED ≠ FIRES. MANUAL_OK ≠ AUTO_FIRES. ONE_PANEL_GREEN ≠ ALL_HEALTHY. Defined ≠ wired. Prove the actual path.
- When Genius asks "you sure?" — re-read the output line by line before answering. Don't double down to be agreeable.
- Label every claim by what kind of proof backs it: verified-in-code (I read the file/call sites this session) / prod-only (only runs on Render, I cannot confirm locally) / needs-Genius-value (depends on a value or click only Genius has) / cannot-physically-click (I have no way to trigger the UI/panel). Never report a fake 100%.

## HOT FILES — EXTREME CARE
These have crashed production before. Edit ONE per change, NEVER batch two hot files together.
1. app/services/ai/reply_service.rb (~2,706 lines — biggest, most-crashed)
2. app/services/games/conversation_orchestrator.rb (~2,418 lines)
3. app/services/games/intent_detector.rb
4. app/services/facebook/chatwoot_bridge_service.rb

Before editing any hot file: read the FULL current version first. After editing: verify every def/if/case/do has a matching end.

## CODING INVARIANTS (learned from real crashes)
- Wrap all Telegram calls in `safe_telegram { ... }`.
- Wrap all external API calls in `begin/rescue StandardError`.
- `useAlert` IS the toast function (composables/index.js) — call it directly `useAlert('msg')`, or alias `const showAlert = useAlert;` with NO parens. NEVER write `useAlert()` — that fires a blank toast on mount and makes the alias undefined.
- Redis locks in Sidekiq: `Sidekiq.redis { |conn| conn.set(...) }` — never `$redis` or `Redis.current`.
- `neighbor` gem needs `.to_a` before pgvector COUNT (avoids double-alias SQL bug).
- DeepSeek reasoning models output in `reasoning_content`, NOT `content` — parser must fall back.
- Vite bundles are committed to git. Frontend changes don't deploy without `pnpm exec vite build` locally + committing `public/vite/`.
- FacebookIdentity#inboxes is a custom method, not an association — `includes(:inboxes)` crashes it.

## KEY IDS
Account 2 · FB Inbox 5 (Channel::Api, working) · Inbox 2 (Channel::FacebookPage, BROKEN — don't use) · Telegram cashout group `-5243223053` · 73,070 RAG pairs in bella_rag_pairs (all account_id=2, all approved=true).

## RAG SYSTEM (current state)
- `IntentRetriever.predict(text:, account_id:)` → single intent label + confidence.
- `IntentRetriever.retrieve(text:, account_id:, top_k:)` → array of top-K cashier example hashes.
- `BellaRagPair.for_scope(account_id:, industry_slug: nil)` — industry_slug is now optional (was a crash bug).
- RAG cutover: when regex returns nil AND RAG confidence ≥ 0.60, route via RAG_TO_INTENT_MAP.
- 27 real_intent labels in DB. RAG_TO_INTENT_MAP currently covers 16 — gap.

## AGENT POLICY ENGINE (it6, shipped)
- Config lives in `account.settings` as an `agent_policy` JSONB column, exposed via `store_accessor`.
- `Games::PolicyResolver` reads it LIVE (no restart) for bonuses / referral / cashout, honoring per-rule time-windows.
- reply_service guards keep Bella honest: `guard_against_policy_freelancing`, `guard_against_invented_balance`, `guard_against_false_load_claim` — she states ONLY configured numbers and defers when policy is empty.
- Multi-op handling: `detect_multi_op` flags a message asking for several actions; `handle_multi_op` composes the existing per-op gated handlers (no new ungated paths).

## HOW WE SHIP — THE LOOP (do not skip)
1. Read actual live code before proposing any change. Never guess at file contents.
2. Make the change. Show the diff.
3. Print a DUMP: files changed, line counts, new method names, exact VERIFY commands, any errors.
4. STOP. Genius pastes the dump to the planning Claude for verification.
5. Genius deploys (you do NOT push). Then Genius reports back.
6. Only then move on — or fix what broke first.

## DEPLOY — GENIUS RUNS THIS, NOT YOU
`clean` is BOTH the Render deploy target AND the source of truth. `origin` is stale and unused — ignore it.
Pull-first flow (Genius runs every line; Claude Code NEVER pushes):
  git checkout -- public/vite/ public/packs/   # drop local bundle churn first
  git clean -fd                                # remove stray untracked files
  git pull clean main --no-rebase              # merge in clean's current state
  # on a bundle conflict: keep OURS on public/vite/ + public/packs/, then rebuild:
  pnpm exec vite build
  git add <specific files> public/vite/ public/packs/
  git commit --no-verify -m "msg"
  git push clean main

NEVER push to clean yourself. Show the diff, print the DUMP, hand off. Genius deploys.
After the push, Genius triggers Manual Deploy on Render (Web Service + Background Worker — both must go green).

## RENDER + GATES
- Render services: web service `srv-d8fos2m`, worker `srv-d8four`. BOTH must go green after a deploy.
- The full money harness and the corpus grader are RENDER-ONLY — NEVER run them locally. `agent_games.credentials` is ActiveRecord-encrypted; running these locally destroys prod panel creds.
- Local gate (all Claude Code may do): `ruby -c <file>` for syntax + the `tmp/bp_section_runner` subset. Anything beyond that is prod-only — label it accordingly.

## DESTRUCTIVE ACTIONS
Never delete code/files without showing a diff and getting an explicit yes. Never run a migration or `update_all` on bella_rag_pairs (73K rows) inside Rails — it times out. Use `psql $DATABASE_URL -c "..."` for bulk DB ops.

## AI PERSONA OUTPUT RULES (when writing Bella's replies/prompts)
Never admit being AI. Max 2 lines. No bullets. No "certainly!" / "great question!". Sound like a human cashier texting on shift, not a chatbot.

## PROMPT/TASK STRUCTURE GENIUS EXPECTS
Every change request: WHAT (2 lines) / WHY (2 lines, beginner-friendly) / READ THIS FIRST (exact files) / DO THIS (exact code) / VERIFY (exact PowerShell command + what success looks like) / DUMP (files+diffs+errors back).

## COMMUNICATION & STOPPING (model-agnostic prompt-craft)
- LEAD WITH THE OUTCOME. The first sentence of any dump or summary is the bottom line — what happened or what you found, the one-line TLDR Genius would ask for. Detail and reasoning come AFTER. Never bury the answer under a wall of log.
- DON'T END ON A PROMISE. If your last paragraph is a plan, a question, or "I'll now run X" / "let me know when…" about work you haven't done — do that work now with the tool call. End your turn only when the task is complete or you're blocked on input only Genius can give (a value, a push, a deploy).
- PAUSE ONLY WHEN GENUINELY NEEDED. Stop and ask only for: a destructive/irreversible action, a real scope change, or input only Genius can provide. For reversible steps that follow from the request, proceed.
- FINAL SUMMARY = RE-GROUNDING, not a continuation of your working thread. It's the first thing Genius sees and he didn't watch the run. Outcome first, then the 1-2 things you need from him, each explained plainly. Drop working shorthand, arrow-chains, and labels you invented mid-run. Give every file / commit / flag / command its own plain-language clause.
- DON'T ECHO YOUR REASONING AS THE ANSWER. Don't transcribe your internal chain-of-thought into the response text.
- DEPLOY DISCIPLINE OVER PROMPT POLISH. A correct, reviewed change still does nothing until it's committed → pushed → both Render services green on the NEW commit → then tested. Code correct on disk ≠ code running in production. (Confirmed the hard way: a correct thinking-mode fix sat un-deployed because the file was committed but the wrong commit was pushed.)
