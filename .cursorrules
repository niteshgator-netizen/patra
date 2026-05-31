# PATRA — CURSOR RULES
# Auto-read by Cursor on every prompt. NON-NEGOTIABLE.

# ─────────────────────────────────────────────────────
# 1. WHO I AM
# ─────────────────────────────────────────────────────
- Name: Genius. Complete coding beginner.
- OS: Windows + PowerShell ONLY. Never give Linux/Mac/bash commands.
- Editor: Cursor Pro. Local repo: C:\Users\kam work\patra
- Explain in plain English. Define every technical term in one line.
- Short, direct answers. No preambles. No filler ("great question", "certainly").
- Push back when a request is bad. Explain why. Propose better.
- Never suggest taking a break or stopping.

# ─────────────────────────────────────────────────────
# 2. PROJECT FACTS (do not guess these)
# ─────────────────────────────────────────────────────
- Patra = forked Chatwoot SaaS unified inbox, live at patrahq.com
- Stack: Ruby on Rails + Vue.js + PostgreSQL + PgVector + Redis + SideKiq
- Deploy: Railway, 4 services (Chatwoot / SideKiq / PgVector / Redis)
- Pre-deploy: bundle exec rails db:chatwoot_prepare && bundle exec rails db:migrate
- Railway internal hostname: http://chatwoot.railway.internal:3000
- Both Chatwoot AND SideKiq must go green or deploy FAILED.
- JWT in localStorage under legacy key `unibox_token` — NEVER rename.
- AI: Grok 4.1 primary, Claude Opus 4.x complex, Gemini Flash OCR, DeepSeek complex replies, Voyage embeddings.
- Game API calls route through SideKiq (different egress IP than Chatwoot).

# ─────────────────────────────────────────────────────
# 3. READ BEFORE EDITING ANY CODE
# ─────────────────────────────────────────────────────
Before ANY edit, read in this order:
1. PATRA_MASTER_COMPLETE.md — single source of truth
2. BUGS_FIXED.md — what's been fixed; never re-introduce
3. PATRA_STATE.md — current state, open threads, next step
4. The actual file you're about to edit — in full. No skimming.

If any of those don't exist, say so. Do not assume.

# ─────────────────────────────────────────────────────
# 4. HOT FILES — EXTREME CARE
# ─────────────────────────────────────────────────────
These crashed Railway before:
1. app/services/ai/reply_service.rb (biggest)
2. app/services/games/conversation_orchestrator.rb
3. app/services/games/intent_detector.rb
4. app/services/facebook/chatwoot_bridge_service.rb

Rules for hot files:
- ONE hot file per task. NEVER two hot files in one run.
- Read the ENTIRE file before editing.
- Verify every def/if/case/do/begin has matching `end` after edits.
- Wrap external API calls in `begin/rescue StandardError`.
- Wrap ALL Telegram calls in `safe_telegram { ... }` blocks.
- If task touches a hot file, START response with:
  HOT FILE: <filename>. Reading full file first. Single-file change only.

# ─────────────────────────────────────────────────────
# 5. DATA SAFETY
# ─────────────────────────────────────────────────────
NEVER, without showing exactly what will change AND getting explicit "yes":
- Delete files
- Delete database rows / drop tables
- Delete environment variables
- Overwrite .env, database.yml, or any credential file
- Force-push to main
- Delete migrations
- Rename variables/methods/files (unless told to)
- Reformat unrelated code
- Delete commented-out code

Bug-fix CODE edits in app/ are fine without extra confirmation.
DATA or CONFIG changes need explicit confirmation.

# ─────────────────────────────────────────────────────
# 6. SCOPE DISCIPLINE
# ─────────────────────────────────────────────────────
- Do EXACTLY what was asked. No bonus changes.
- See something else to fix? Call it out at END, do not fix it.
- No premature optimization. No unused features. YAGNI.

# ─────────────────────────────────────────────────────
# 7. CODE QUALITY
# ─────────────────────────────────────────────────────
- Production-grade only. NO placeholder, NO TODO, NO dummy data, NO tutorial comments.
- Don't know something? STATE it as unknown. Never guess.
- Match existing code style. Don't reformat unrelated code.

## Ruby / Rails
- Service objects in app/services/
- 2-space indent, no tabs
- snake_case methods, CamelCase classes
- `private` for non-public methods
- Logging prefix matches service: [ReplyService], [ImagePaymentExtractor], [FacebookBridgeJob], [HaikuClient]
- New AI calls: `defined?(ClassName)` + `begin/rescue StandardError`
- Rails.logger.info/.warn/.error — NEVER `puts` in app code

## Vue (frontend)
- Composition API for NEW code; Options API only if file already uses it
- Use existing design tokens / CSS variables — no new colors
- PascalCase for Vue components

## Database
- Every new column needs a migration. NEVER edit schema.rb manually.
- Migration filename: YYYYMMDDHHMMSS_descriptive_name.rb
- Indexes for foreign keys + frequently-queried columns

# ─────────────────────────────────────────────────────
# 8. END EVERY TASK WITH THIS DUMP
# ─────────────────────────────────────────────────────
After completing any task, print this dump as your final output.
User pastes it back to Claude for verification BEFORE deploy.
Do NOT skip this dump.

=== CURSOR DUMP ===
FILES CHANGED:
  - <full path 1>
  - <full path 2>

DIFF SUMMARY:
  <file 1>: +X lines / -Y lines

KEY CHANGES (one line each):
  - <what changed and why>

COMMANDS RUN:
  - <command 1>

OUTPUT / ERRORS:
  <paste test output, syntax errors, lint warnings>

HOT FILES STATUS:
  - app/services/ai/reply_service.rb [untouched / touched]
  - app/services/games/conversation_orchestrator.rb [untouched / touched]
  - app/services/games/intent_detector.rb [untouched / touched]
  - app/services/facebook/chatwoot_bridge_service.rb [untouched / touched]

VERIFY STEPS (PowerShell, exact commands):
  1. <command>
  2. <expected output>

ROLLBACK COMMAND (if this breaks prod):
  git revert HEAD && git push
=== END DUMP ===

# ─────────────────────────────────────────────────────
# 9. ENVIRONMENT QUIRKS
# ─────────────────────────────────────────────────────
- Windows RDP clipboard fails over ~28k chars — split large pastes.
- VPS .env: edit via PowerShell `-replace` only. Notepad doubles variable names.
- VPS Python: use `python` not `py -3.12`.
- Type SSH commands FRESH — PowerShell bracket-paste corrupts them.

# ─────────────────────────────────────────────────────
# 10. WHEN UNCERTAIN
# ─────────────────────────────────────────────────────
- STOP. State the uncertainty clearly.
- Re-read the relevant file.
- Ask ONE specific question.
- Do NOT guess and proceed.

# ─────────────────────────────────────────────────────
# 11. GIT
# ─────────────────────────────────────────────────────
- Commit format: short imperative + scope. Examples:
  fix(reply_service): premature 'loaded' message before IMAP verify
  feat(games): add Vegas Sweeps URL config
- NEVER force-push to main.
- NEVER squash without asking.

# ─────────────────────────────────────────────────────
# 12. WHAT NOT TO DO
# ─────────────────────────────────────────────────────
- Do not invent file paths. If file doesn't exist, say so.
- Do not invent method names. Check the file first.
- Do not write tests unless asked.
- Do not refactor unless asked.
- Do not "improve" code that wasn't part of the task.
- Do not add dependencies (gems, npm packages) without approval.
- Do not change Ruby/Rails/Vue/Node versions.

# END
