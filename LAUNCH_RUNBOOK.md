# PATRA LAUNCH RUNBOOK
(TAB B, launch night 2026-06-10. Companion docs: PATRA_LAUNCH_LOG.md for what changed,
SECRETS_ROTATION_RUNBOOK.md for secrets, docs/PATRA_BACKEND_MAP.md for architecture.)

## ROLLBACK HASHES
- TAB B run start (pre-everything): `5bfb2862a396b21f95361d1dd9dcc01637ec04a4`
- To roll back a single TAB B change: `git revert <commit> --no-edit` (every commit is
  prefixed `patra-launch:`). NEVER `reset --hard` — three tabs committed to main tonight.

## DEPLOY RITUAL (Genius runs this — standard sequence)
```
git add <specific files>
git add public/vite/
git commit --no-verify -m "msg"
git push clean main --force      # clean = Render deploy mirror
git push origin main             # backup; NO --force (rebase dance if rejected)
```
Then Render → Manual Deploy on BOTH services (Web Service + Background Worker) → both green.

## PRE-LAUNCH CHECKLIST (in order)
1. **Render Postgres backup**: Render dashboard → patra Postgres → Backups → "Create
   backup" (manual snapshot) BEFORE deploying launch changes. Confirm the backup shows
   in the list. (Render also keeps daily automatic backups — verify the latest one is
   recent.)
2. Deploy (ritual above), both services green.
3. Render Shell (web service): `bundle exec rails runner script/patra_data_integrity.rb`
   → expect ALL CLEAN (read-only; investigate anything flagged).
4. Render Shell: `ruby script/patra_launch_readiness.rb` → expect READY. Section 5b is
   new tonight (env completeness, HB endpoint routing, telegram secret posture,
   no-tracked-secrets).
5. Run the new spec files (see SPECS-UNRUN list in PATRA_LAUNCH_LOG.md):
   `bundle exec rspec spec/services/games/money_handlers_spec.rb spec/services/games/action_executor_spec.rb spec/services/ai/deepseek_client_spec.rb` (full list in the log).
6. Telegram webhook hardening rollout (two-step, do NOT skip step a):
   a. re-save every Telegram channel (re-registers webhook with derived secret), then
   b. set `TELEGRAM_WEBHOOK_VALIDATE_SECRET=true` on both Render services + redeploy.
7. Secrets rotation: TELEGRAM_BOT_TOKEN and JUWA_SECRET_KEY are CONFIRMED exposed in
   git history → rotate per SECRETS_ROTATION_RUNBOOK.md (priority 1 + 2).

## MONITORING CHECKPOINTS (launch day)
- **BetterStack health endpoint**: Chatwoot exposes `GET /health` (rack-attack safelisted,
  never throttled). Point the BetterStack uptime monitor at `https://patrahq.com/health`
  expecting HTTP 200; alert channel = the ops Telegram group. Also monitor
  `https://patrahq.com/api` for app-level liveness.
- **Money flow**: log search for `[MONEY]` (new structured line on every audited game
  action: type/ok/amount/account/contact/game/order/code). A burst of `ok=false` on one
  game = panel down (check AgentGame degraded + Telegram GAME DOWN alert).
- **Telegram**: `[TelegramWebhook]` warns = forged/old webhooks hitting the endpoint;
  `[TelegramEventsJob] duplicate update_id` = retries being deduped (normal in bursts).
- **FB tokens**: `PAGE TOKEN DEAD` in logs / Telegram "FB PAGE TOKEN DEAD" alert →
  re-connect page via patra/fb_connect.
- **Sidekiq**: readiness script section 5 (queue latency); `low` queue backing up =
  IMAP/memory-rotation jobs stuck.
- **Sentry**: message bodies/passwords/tokens are scrubbed (`[SCRUBBED]`) as of tonight —
  if you see raw player text in an event, the scrub list in
  config/initializers/sentry.rb needs the new key added.

## RATE LIMITS ADDED TONIGHT (env-tunable, conservative)
| Throttle | Default | Env var |
|---|---|---|
| POST /webhooks/telegram/* per IP | 120/min | RATE_LIMIT_TELEGRAM_WEBHOOK |
| Live-AI endpoints per IP | 30/min | RATE_LIMIT_PATRA_AI |
| Cashier claim/complete per IP | 30/min | RATE_LIMIT_CASHIER_CLAIMS |

## DEPENDENCY REPORT (DEP — report-only tonight, no changes made)
- **npm (TAB A owns toolchain — DO NOT change tonight)**: `pnpm audit --prod` =
  9 vulnerabilities: 1 high (glob 10.2–10.5 CLI command injection via `-c/--cmd` —
  build-time CLI vector only, not runtime-exploitable in the app), 7 moderate,
  1 low (min-document prototype pollution via video.js chain). Plan: after launch,
  `pnpm update glob` (>=10.5.0) and bump video.js; re-run `pnpm audit`.
- **Gemfile**: rails 7.1.5.2 / rack 3.2.6 / nokogiri 1.19.3 / sidekiq 7.3.1 /
  devise 4.9.4 / puma 6.4.3 — all current patch lines as of tonight. bundler-audit could
  NOT run locally (local ruby 3.4.9 vs Gemfile 3.4.4 — bundler refuses). Plan: on Render
  Shell run `gem install bundler-audit && bundle-audit check --update`; apply only
  patch-level bumps.
- No Gemfile/package.json changes were made (apply-condition "bundle install stays
  clean" unverifiable locally — see DECISIONS in PATRA_LAUNCH_LOG.md).

## LAUNCH-DAY QUICK TRIAGE
| Symptom | First move |
|---|---|
| Bella silent account-wide | Check ai_paused custom attr (incident pause), business hours/holiday rows, DeepSeek ping (readiness §2) |
| Loads failing on one game | AgentGame status (degraded?), `[MONEY] ok=false` codes, panel session (ASP.NET refresh logs) |
| Duplicate player messages | Telegram dedup logs; FB bridge double-delivery |
| Payment verified but no announce | ImapCheckJob lock + low queue latency; announce job duplicate-guard log line |
| 401s on telegram webhook | TELEGRAM_WEBHOOK_VALIDATE_SECRET flipped before webhooks re-registered — re-save channels or set flag back to unset |
| Everything on fire | `git revert` the suspect `patra-launch:` commit(s), redeploy; rollback hash above is the pre-run state |
