# PATRA HARDENING RUN LOG — 2026-06-10

## ROLLBACK HASH (state before this run)
```
3a46f24e411be564b3e821ea201e290c60cb9e4c
```
To roll back everything from this run: `git reset --hard 3a46f24e411be564b3e821ea201e290c60cb9e4c`

## MORNING SUMMARY (read this first)
ALL 13 ITEMS DONE + self-audit green. 13 commits after the rollback hash (one per item + log
init), each with explicit paths, NOTHING PUSHED. Verified end-of-run: 41 touched .rb files
all `ruby -c` Syntax OK; 12 pure-Ruby self-tests ALL PASS (221 asserts total, run against the
REAL edited files with stubs); `git diff --name-only <rollback>..HEAD` shows ZERO hot files
(reply_service / orchestrator / intent_detector / chatwoot_bridge untouched) and ZERO
owner-WIP files (telegram_notifier / winback_service / base_provider / outbound_dispatcher /
zernio_provider untouched — winback/telegram_notifier were READ only). The 7 proof scripts
are untouched; one NEW read-only script added (patra_panda_probe.rb). RSpec suite not
runnable locally (bundler exit 127, same as overnight run) → all RSpec files are SPECS-UNRUN
with exact commands below.

What changed, one line each:
- H1 backup ban alerts no longer crash the hourly sweep (public api_error + per-page rescue).
- H2 warming clock now runs from a real start stamp; day 2 can no longer promote; promote
  needs day>=7 AND fresh health.
- H3 page-switch no longer mass-blasts every contact: 1 operator Telegram + capped (50,
  env-tunable) rate-limited notes only to contacts active in the last 24h.
- H4 the two ".rb" cron names fixed (classes were fine — they were almost certainly RUNNING,
  not dead); all 30 crons audited; 7 sweep jobs got per-record rescues.
- H5 the three SLA settings (toggle / first-response / resolution) actually drive alerts now,
  including a new once-per-conversation resolution alert.
- H6 webhook_url is real: Patra::WebhookEmitter sends payment.confirmed, load.success,
  load.failed, cashout.executed — async, no-op without URL, can't touch the money path.
- H7 panda blank balance diagnosed (silently-returned 301 body); family client now follows
  one same-host redirect and errors LOUDLY otherwise; run patra_panda_probe.rb on Render to
  confirm the 301's Location (the one open question).
- H8 FB token refresh failures / dying tokens now Telegram-alert once per token per day.
- H9 stuck-pending alert verified already-working; sweep got a per-row rescue.
- H10 AI ReplyJob: any error now releases the reply lock so the bounded Sidekiq retry isn't
  eaten as a "duplicate" (lost replies); retries stay bounded at 3/5.
- H11 shared re-engage cooldown verified across ALL senders (incl. winback, read-only);
  default window raised 24h → 72h; full sender map in PATRA_REENGAGE_MAP.md.
- H12 PATRA_RESTRICT_MONEY_ACTIONS dark flag shipped OFF — flip it on Render to make money
  endpoints + money-config mutations admin-only (confirm your user is administrator first).
- H13 /terms + /privacy ALREADY EXISTED and resolve (the 404 premise was stale); added
  OPERATOR-CONFIRM markers (support@ email, Delaware) + fixed dead landing-footer links.

MORNING RENDER WALL (Render Web Shell, in order):
```
bundle exec rails runner "puts 'boot ok'"
bundle exec rails runner script/patra_money_harness.rb        # expect 57/57
bundle exec rails runner script/patra_money_preflight.rb      # expect 28/28
bundle exec rails runner script/patra_intent_suite.rb         # expect 128/128
bundle exec rails runner script/patra_reply_smoke.rb          # expect 100/100 asserts
bundle exec rails runner script/patra_rules_consistency_check.rb
bundle exec rails runner script/patra_launch_readiness.rb
bundle exec rails runner script/patra_balance_probe.rb
bundle exec rails runner script/patra_panda_probe.rb          # NEW — decides the H7 301 question
```
Then the run's RSpec files (see SPECS-UNRUN section) — single command:
```
bundle exec rspec spec/jobs/backup/health_check_job_spec.rb spec/services/backup/drip_scheduler_spec.rb spec/services/backup/customer_migration_spec.rb spec/configs/schedule_classes_spec.rb spec/configs/schedule_spec.rb spec/jobs/sla/check_violations_job_spec.rb spec/services/patra/webhook_emitter_spec.rb spec/services/games/asp_net_panel/base_client_redirect_spec.rb spec/jobs/patra/refresh_fb_tokens_job_spec.rb spec/jobs/pending_payment_timeout_job_spec.rb spec/jobs/ai/reply_job_lock_spec.rb spec/services/reengagement/contact_cooldown_spec.rb spec/controllers/api/v1/accounts/patra/money_action_guard_spec.rb spec/requests/legal_pages_spec.rb
```
Operator decisions for the morning:
1. H12: flip PATRA_RESTRICT_MONEY_ACTIONS=true on Render? (1-minute decision from
   PATRA_ROLES_AUDIT.md — confirm your own user is administrator first.)
2. H7: read patra_panda_probe.rb output — if Location is a different host/port, update
   BASE_URL in panda_master/client.rb + SessionRefresher::BASE_URLS (2-line change).
3. H13: confirm support@patrahq.com is monitored + Delaware is the formation state
   (OPERATOR-CONFIRM markers in app/views/legal/*.html.erb).

## QUEUE
- [x] H1 backup ban-alert crash (health_check_job.rb per-page rescue + public api_error) —
  HANDOFF-B-4 diff applied verbatim. Proof (a): tmp/self_tests/h1_backup_health_check_test.rb
  ALL PASS (10 asserts, real job file loaded, private-notify trap in place) + ruby -c OK.
  RSpec spec/jobs/backup/health_check_job_spec.rb written (SPECS-UNRUN locally).
- [x] H2 warming clock (drip_scheduler.rb warming_started_at stamp + phase floor + day-7 gate) —
  rewrite per HANDOFF-B-5: clock from stats['warming_started_at'] (stamped once, lazily on first
  hourly sweep after entering warming, accurate to <=1h); phase = highest schedule key <= elapsed
  days (day 0 = 'pre_warm'); promote ONLY when days >= 7 AND health_ok?. Proof (a):
  tmp/self_tests/h2_drip_scheduler_test.rb ALL PASS (21 asserts — days 0/1/2/3/6/7/8, stale-health
  day 7, fresh-updated_at immunity, stamp-once, garbage-stamp) + ruby -c OK. RSpec
  spec/services/backup/drip_scheduler_spec.rb written (SPECS-UNRUN locally).
- [x] H3 customer-migration mass-blast → operator alert + 24h-window capped notes —
  rewrite per HANDOFF-B-6: ONE Telegram api_error operator alert (fires first, rescued,
  carries from/to page + contact count); "we moved" note ONLY when the contact has an INBOUND
  message in the last 24h (last_activity_at pre-filter + authoritative inbound check);
  cap PATRA_MIGRATION_MAX_NOTES (default 50, 0 = alert-only, garbage → default); 1 note/sec;
  per-contact rescue; cap-skips logged. account stamp now records notes_sent. Proof (a):
  tmp/self_tests/h3_customer_migration_test.rb ALL PASS (13 asserts) + ruby -c OK.
  RSpec spec/services/backup/customer_migration_spec.rb written (SPECS-UNRUN locally).
  BackupPages stay standby — nothing in H1-H3 activates anything.
- [x] H4 dead crons + full cron audit. FINDING (a, read-verified): the two ".rb" entries were
  NAME-malformed only — sidekiq-cron names are labels; both classes
  (Internal::RemoveStaleContactInboxesJob / RemoveStaleRedisKeysJob) exist and were resolvable,
  so the jobs were likely RUNNING under ugly names, not dead. Fixed anyway: renamed both keys
  (no other same-pattern siblings — checked all 30), added old .rb names to the sidekiq.rb
  explicit-destroy list so stale Redis entries are cleaned on deploy.
  AUDIT of all 30 crons: every class resolves to a real file (90/90 asserts). Per-record-rescue
  fixes applied (non-hot, non-WIP): contacts/lifecycle_update_job (per-contact),
  contacts/segmentation_job (per-contact), contacts/activity_score_job (per-account),
  cashier/expire_claims_job (per-claim), payments/handle_health_monitor_job (per-account),
  contacts/re_engage_job (per-contact), reengage_dormant_contacts_job (per-account + .to_i on
  reengage_days — string value would have raised on "14".days).
  Already-safe (verified): daily_summary, send_scheduled, proactive_session_refresh, email_poll
  (per-inbox), imap_check (per-handle/per-contact), shift_report, rotate_player_memory,
  dormant_player_job, refresh_fb_tokens, winback (owner-WIP service — per-account+per-contact
  rescue VERIFIED by read, no change needed). Stock Chatwoot trigger/housekeeping jobs
  (trigger_*, delete_accounts, periodic_assignment, remove_old_notification, remove_orphans,
  fetch_imap, remove_stale_*) delegate to per-record sub-jobs or are upstream-stable —
  REPORT-ONLY, no edits (fork-divergence not worth it). Sla::CheckViolationsJob per-account
  rescue lands with H5. Proof: tmp/self_tests/h4_schedule_classes_test.rb ALL PASS (90) +
  spec/configs/schedule_classes_spec.rb (constantize + performable on Render) + ruby -c OK on
  all 9 touched files.
- [x] H5 SLA wiring — HANDOFF-B-1 applied + extended: sla_alerts_enabled=false skips the
  account (default true when unset, string "false" honored); first_response threshold =
  custom_attributes['first_response_limit_minutes'] with policy fallback; NEW check_resolution
  mirror on resolution_limit_minutes (policy resolution_time_threshold fallback — column
  verified in schema:1203) alerting ONCE per conversation via durable Redis stamp (7d TTL,
  key sla_resolution_violated_<id>); accounts with custom limits now checked even with ZERO
  sla_policies (the settings page's whole point); per-account rescue added (H4 promise).
  Proof (a): tmp/self_tests/h5_sla_check_test.rb ALL PASS (12 asserts) + ruby -c OK.
  RSpec spec/jobs/sla/check_violations_job_spec.rb written (SPECS-UNRUN locally).
- [x] H6 Patra::WebhookEmitter — NEW app/services/patra/webhook_emitter.rb +
  app/jobs/patra/webhook_emit_job.rb. emit() = no-op without webhook_url, enqueue-only (zero
  inline network I/O in the money path), enqueue failures swallowed; deliver() (in the job) =
  3s timeout, ONE retry, every error rescued, never raises → job never retry-storms. Body
  {event, account_id, timestamp, payload}. HMAC X-Patra-Signature when
  custom_attributes['webhook_secret'] set (no UI field exists yet — DOCUMENTED in the class
  header; set via console/custom_attributes). Seams wired (both NON-HOT): action_executor
  log_money [MONEY] site → load.success/load.failed (action_type load|recharge) +
  cashout.executed (action_type cashout, ok only); payments/email_confirmation_service
  check_entry confirm site → payment.confirmed. Both seam calls additionally rescued.
  Proof (a): tmp/self_tests/h6_webhook_emitter_test.rb ALL PASS (17 asserts) + ruby -c OK x4.
  RSpec spec/services/patra/webhook_emitter_spec.rb (webmock) written (SPECS-UNRUN locally).
- [x] H7 panda master blank balance — DIAGNOSIS (a, verified by read):
  base_client.rb let ANY redirect response fall through the final guard (`unless success ||
  redirection`) and be RETURNED with its 0-byte body → extract_agent_balance → nil, silently.
  That exactly produces "session refresh WORKS + 301 + 0-byte + balance nil". Root cause of
  the 301 itself = (c) assumption until probe runs: panda is the ONLY family panel on default
  port 443 (orion/milky :8781, fire_kirin :8888) → most likely a same-host canonicalization
  bounce (www/scheme/path), possibly a moved host. FIX (family client, additive): follow ONE
  same-host non-login redirect on GET (before the CapSolver refresh path — valid sessions no
  longer burn refresh attempts on a bounce); login-page redirects (default.aspx/root) still
  take the reactive-refresh path; ANY unresolved redirect now raises Games::ClientError
  carrying the Location header instead of returning empty. If the probe shows a cross-host
  Location, update BASE_URL in panda_master/client.rb + SessionRefresher::BASE_URLS (probe
  prints this interpretation). NEW script/patra_panda_probe.rb (read-only: GETs with stored
  session cookie, prints status/Location/body-len/markers/all hops; zero writes).
  Proof (a): tmp/self_tests/h7_redirect_follow_test.rb ALL PASS (9 asserts incl. orion-style
  no-redirect path untouched: zero behavior change when no redirect occurs) + ruby -c OK x2.
  RSpec spec/services/games/asp_net_panel/base_client_redirect_spec.rb (SPECS-UNRUN locally).
- [x] H8 FB token expiry alerting — refresh_fb_tokens_job now fires ONE
  Games::TelegramNotifier.api_error per inbox token per day (Redis stamp
  patra:fb_token_alert:<inbox_id>, 24h TTL) on: refresh returning blank, refresh raising
  (alert then re-raise into the existing per-inbox rescue), or token expiring with NO refresh
  path (no fb_user_long_lived_token AND obtained_at older than 53d = 60d Meta lifetime − 7d
  warning window — lifetime is (c) assumption, documented in-code; unknown-age tokens also
  warn). Healthy refreshes stay silent. Alert helper never raises.
  Proof (a): tmp/self_tests/h8_fb_token_alert_test.rb ALL PASS (12 asserts) + ruby -c OK.
  RSpec spec/jobs/patra/refresh_fb_tokens_job_spec.rb written (SPECS-UNRUN locally).
- [x] H9 stuck-pending sweeper — VERIFIED (a): alert_stuck_game_actions already alerts (not
  just logs) via api_error for GameActions pending >1h, throttled 1/hour via Redis setex
  'patra:stuck_pending_alert', read-only (no status mutation), alert failures rescued. Only
  gap fixed: per-conversation rescue in the reminder sweep (one corrupt row could previously
  kill the run before reaching the stuck-action alert). Note: throttle is GLOBAL across
  accounts (fine for single-account prod; logged, not changed).
  Proof (a): tmp/self_tests/h9_stuck_pending_alert_test.rb ALL PASS (10 asserts incl.
  mutation-trap structs proving read-only) + ruby -c OK.
  RSpec spec/jobs/pending_payment_timeout_job_spec.rb written (SPECS-UNRUN locally).
- [x] H10 ReplyJob rescue posture — VERIFIED existing (a): retry_on StandardError attempts:3 +
  TransientSendError attempts:5, both with give-up logs (bounded, no infinite loop);
  TransientSendError already released the lock. GAP FIXED: any OTHER StandardError left the
  30s REPLY_LOCK held, and the first polynomially_longer retry (~3-18s) hit it and became a
  "skipping duplicate reply" no-op → reply silently lost. Added generic rescue: release lock,
  log, re-raise (retry stays bounded). Job file non-hot ✓.
  Proof (a): tmp/self_tests/h10_reply_job_lock_test.rb ALL PASS (10 asserts — both branches
  mocked, duplicate-skip + happy path unchanged) + ruby -c OK.
  RSpec spec/jobs/ai/reply_job_lock_spec.rb written (SPECS-UNRUN locally).
- [x] H11 re-engagement shared cooldown — FINDING (a): the shared mechanism ALREADY existed
  (Reengagement::ContactCooldown, built by a prior run) and is honored by all three real
  senders: Contacts::ReEngageJob (08:00, check :38 / stamp :45), Reengagement::SendService
  for DormantPlayerJob (12:00, check :18 / stamp :73), Games::WinbackService (17:00, check :70
  / stamp :311 — owner-WIP, VERIFIED BY READ ONLY, zero edits). ReengageDormantContactsJob
  (09:00) is log-only and sends nothing. Crons already staggered 08/09/12/17.
  Changes this run: DEFAULT_HOURS 24 → 72 (per H11 spec; safe direction — fewer pings; env
  PATRA_REENGAGE_COOLDOWN_HOURS still overrides) + NEW PATRA_REENGAGE_MAP.md (full sender map).
  DEFERRED-WIP: none needed — winback already integrated, no diff required.
  Proof (a): tmp/self_tests/h11_shared_cooldown_test.rb ALL PASS (12 asserts — REAL job + REAL
  service cross-sender both directions + 71h/73h window boundaries + env override/garbage)
  + ruby -c OK. RSpec spec/services/reengagement/contact_cooldown_spec.rb (SPECS-UNRUN locally).
- [x] H12 role guards dark flag — HANDOFF-B-3 applied as shared concern
  Patra::MoneyActionGuard (exact `ENV['PATRA_RESTRICT_MONEY_ACTIONS'].to_s == 'true'`
  semantics from the logged diff; default OFF = the before_action returns immediately, zero
  behavior change). Guarded when ON (admin-only): agent_games
  load_player/cashout_player/add_player/reset_player_password; game_rules#update;
  player_tiers create/update/destroy/bulk_assign; reply_preference#update;
  referrals create/update (update_settings was already admin-only). All reads stay open.
  Proof (a): tmp/self_tests/h12_money_guard_test.rb ALL PASS (5 asserts — unset/false/1/TRUE
  are no-ops, only exact 'true' guards) + ruby -c OK x6. RSpec request spec
  spec/controllers/api/v1/accounts/patra/money_action_guard_spec.rb covers both flag states
  + admin pass + reads-open (SPECS-UNRUN locally).
- [x] H13 terms/privacy — PREMISE STALE (a, verified): /terms + /privacy ALREADY EXIST and
  resolve — routes.rb:15-16 → LegalController (unauthenticated, layout 'legal' with full
  Patra-branded styling) → comprehensive real ToS (17 sections incl. AI features, billing,
  Meta platform terms, indemnification, Delaware governing law) + Privacy Policy (12 sections
  incl. Meta data-deletion flow, GDPR/CCPA rights, retention table) dated May 9 2026. Signup
  TERMS_ACCEPT (en) links https://www.patrahq.com/terms + /privacy → resolve. No 404 in code.
  Changes this run: OPERATOR-CONFIRM erb comments added on the contact-email blocks (both
  pages) + governing-law state (terms §14) — confirm support@patrahq.com is monitored and
  Delaware is the real formation state; landing page footer Legal links fixed from dead
  href="#" to /privacy + /terms (public/patra-landing.html:895 — static file, no vite build
  needed); NEW spec/requests/legal_pages_spec.rb (unauthenticated 200 + route_to proof).
  NOTE for operator: if a 404 was seen live, it predates routes.rb:15-16 or was on a host not
  running this app (www vs apex DNS) — the morning spec run settles it.
- [x] FINAL self-audit + DUMP (see FINAL SELF-AUDIT section)

## PHASE 0 — READ REPORT (return shapes, verified by read 2026-06-10)
- `Games::TelegramNotifier.api_error(account:, message:, details: nil)` — PUBLIC class method,
  returns `{ ok:, channels:/error:/reason: }` hash, never raises (notify has its own rescue).
  `.notify` is PRIVATE keyword-only (telegram_notifier.rb:162) — confirmed H1 crash class.
- `Backup::HealthCheckJob#perform` — `BackupPage.find_each { check_page }`, NO per-page rescue;
  `notify_ban`/`notify_swich` call private `notify` positionally at :64/:69 → NoMethodError. Confirmed.
- `Backup::DripScheduler#advance_warming` — days from `updated_at` (touched hourly by
  health_check_job:20 `update!(health_check_at:)`); `WARMING_SCHEDULE[days]` exact-match {1,3,7},
  else falls to `values.last` = 'fully_active'. Both HANDOFF-B-5 bugs confirmed by read.
- `Backup::CustomerMigration.migrate(account, from:, to:)` — posts MessageBuilder message to EVERY
  contact's last conversation, no cap/window/tag; then stamps account custom_attributes. Confirmed.
- `Sla::CheckViolationsJob` — reads `account.sla_policies` + `policy.first_response_time_threshold`
  only; no custom_attributes read; no resolution check; Redis::Alfred 1h stamp + 
  `Audit::TelegramNotifier.sla_violation`. Confirmed HANDOFF-B-1.
- Settings controller persists webhook_url / first_response_limit_minutes / resolution_limit_minutes /
  sla_alerts_enabled into account.custom_attributes (settings_controller.rb:32-38). Confirmed.
- `Games::ActionExecutor#log_money(action, ok:, code: nil)` — the [MONEY] seam (action_executor.rb:369),
  called from execute_in_audit success + both failure rescues. Never raises. H6 emit seam.
- Panda: `Games::PandaMaster::Client < AspNetPanel::BaseClient`, BASE_URL https://pandamaster.vip
  (ONLY family member on default port 443; orion :8781, milky_way :8781, fire_kirin :8888).
  `base_client.rb http_request`: any redirect → session_expired? → refresh+retry once; a STILL-redirecting
  retried response passes the `unless success || redirection` guard at :405 and is RETURNED with its
  0-byte body → extract_agent_balance → nil. Silent-nil path confirmed by read (a). Root cause of the
  301 itself needs the Render probe (local probe: panels 500 NullRef on requests without real session).
- `Patra::RefreshFbTokensJob` — per-inbox rescue ✓; refresh failure (blank token) silently returns,
  identity flips to 'expired' silently — NO alerting anywhere. H8 gap confirmed.
- `PendingPaymentTimeoutJob#alert_stuck_game_actions` — ALREADY alerts via api_error, redis setex 1h
  throttle 'patra:stuck_pending_alert', rescued. H9 = verify + spec only.
- `Ai::ReplyJob` — retry_on StandardError(3) + TransientSendError(5); TransientSendError rescue
  releases REPLY_LOCK + re-raises ✓. GAP: generic transient errors (e.g. raised inside ReplyService
  before/at send) do NOT release the 30s lock; first Sidekiq retry (~3-18s, polynomially_longer)
  hits the still-held lock → "skipping duplicate reply" → reply lost. H10 fix: rescue StandardError
  → release lock → re-raise.
- Reengagement: `Reengagement::ContactCooldown` ALREADY EXISTS (contact_cooldown.rb) — honored by
  Contacts::ReEngageJob (:38,:45), Reengagement::SendService (:18,:73 — used by DormantPlayerJob),
  Games::WinbackService (grep hit). Crons already staggered 08/09/12/17 with comment. 
  ReengageDormantContactsJob (09:00) is LOG-ONLY (Rails.logger.info, sends nothing).
  H11 = write PATRA_REENGAGE_MAP.md + cross-sender spec; code likely needs nothing.
- H13: /terms + /privacy ALREADY EXIST — routes.rb:15-16 → LegalController (layout 'legal') +
  full professional ToS/Privacy views (May 9 2026). 404 premise is STALE. Remaining: 
  OPERATOR-CONFIRM markers on contact-email/governing-law lines + routing proof.
- Local environment: ruby 3.4.9 OK; `bundle exec rspec` exit 127 → ALL specs SPECS-UNRUN locally,
  proof via ruby -c + tmp/self_tests pure-Ruby harnesses (overnight-run pattern); exact Render
  commands listed per item.

## DECISIONS
- D0: Specs written as RSpec files for Render + pure-Ruby self-tests under tmp/self_tests/ that run
  locally (bundle/rspec unavailable locally, exit 127 verified). Matches overnight-run proof pattern.
  NOTE: tmp/self_tests is gitignored (same as overnight run) — self-tests live locally only; their
  results are recorded per item in this log.
- D0b: Local probe of panel endpoints attempted (read-only GETs) — both panda AND orion return
  HTTP 500 NullRef pages to non-session traffic from this machine, so the 301-vs-200 difference is
  only observable with real session cookies → Render probe script is the deciding artifact.
- D1 (H3): PATRA_MIGRATION_MAX_NOTES accepts 0 as a deliberate "alert-only, zero auto-notes" mode;
  non-numeric values fall back to the default 50. Operator alert fires FIRST so it survives any
  note-path failure. Eligibility = real INBOUND message in 24h (last_activity_at alone also moves
  on outbound, would over-send).
- D2 (H4): two cron entries were name-malformed only — both classes exist and resolved, so "dead"
  is unproven; (c) they were most likely running under the ugly names. Renamed anyway + added the
  old names to the sidekiq.rb destroy list (idempotent). Stock Chatwoot housekeeping jobs left
  unedited (delegate to per-record sub-jobs / upstream-stable; fork-divergence not worth it) —
  report-only.
- D3 (H5): resolution alert stamp = Redis with 7-day TTL (not conversation.additional_attributes —
  a Conversation update! fires dispatcher callbacks/webhooks; Redis matches the existing
  first-response stamp pattern). Accounts with custom limits are checked even with zero
  sla_policies — otherwise the settings fields would still be dead.
- D4 (H6): webhook delivery is enqueue-only from product code (Patra::WebhookEmitJob on :low),
  never inline HTTP in the money path — "3s timeout + 1 retry" lives in the job's deliver().
  HMAC secret read from custom_attributes['webhook_secret'] (no UI field yet — documented in the
  class header). Ghost-payment ingestion (ghost_payment_store.rb:134) also marks confirmed but was
  NOT wired this run (kept to the two seams the spec named) — future seam, zero risk to add.
- D5 (H7): fix is family-wide (base_client) but ADDITIVE: panels that never redirect (orion etc.)
  have byte-identical behavior (self-test case asserts zero extra requests). Following is limited
  to GET + same host family + non-login target + once. (a) silent-301-return verified by read;
  (c) "follow fixes panda" is the assumption the probe script confirms/refutes.
- D6 (H8): Meta page-token lifetime assumed ~60d → warn at 53d when no refresh path exists;
  unknown-age tokens with no refresh path also warn (weekly cron + 24h stamp = max 1 ping/week).
- D7 (H10): the generic rescue releases the lock for PERMANENT errors too — safe because retry_on
  caps at 3 attempts with a give-up log; the alternative (lock held) silently eats retries.
- D8 (H11): DEFAULT_HOURS 24 → 72 per the H11 spec — strictly less outbound (safe direction);
  PATRA_REENGAGE_COOLDOWN_HOURS still overrides. Winback already honored the shared key —
  verified by read, zero WIP edits needed.
- D9 (H12): guard uses the exact HANDOFF-B-3 semantics (string 'true' only). Implemented as one
  concern instead of 5 copy-pasted methods. player_tiers#bulk_assign added to the guarded set
  (it mutates tier assignment = money-adjacent).
- D10 (H13): did NOT rewrite the legal pages — they already exist, are comprehensive, and predate
  this run (May 9 2026); rewriting working legal copy overnight is risk without benefit. Added
  only the OPERATOR-CONFIRM markers the spec asked for + fixed the landing footer's dead links +
  added the route/render spec that settles the "404" claim on Render.

## DEFERRED-WIP
- (none required) — winback_service.rb / telegram_notifier.rb / base_provider.rb /
  outbound_dispatcher.rb / zernio_provider.rb were not touched and needed no diffs: winback's
  shared-cooldown integration already exists (verified by read, winback_service.rb:70,:311).
- Future (non-WIP) seam noted, not done: emit payment.confirmed from ghost_payment_store.rb:134
  ingestion-time confirmations (D4).

## DEFERRED-WIP
(collected as found)

## SPECS-UNRUN (exact Render commands)
- H1: `bundle exec rspec spec/jobs/backup/health_check_job_spec.rb` (local equivalent ran:
  `ruby tmp/self_tests/h1_backup_health_check_test.rb` → ALL PASS 10)
- H2: `bundle exec rspec spec/services/backup/drip_scheduler_spec.rb` (local equivalent ran:
  `ruby tmp/self_tests/h2_drip_scheduler_test.rb` → ALL PASS 21)
- H3: `bundle exec rspec spec/services/backup/customer_migration_spec.rb` (local equivalent ran:
  `ruby tmp/self_tests/h3_customer_migration_test.rb` → ALL PASS 13)
- H4: `bundle exec rspec spec/configs/schedule_classes_spec.rb spec/configs/schedule_spec.rb`
  (local equivalent ran: `ruby tmp/self_tests/h4_schedule_classes_test.rb` → ALL PASS 90)
- H5: `bundle exec rspec spec/jobs/sla/check_violations_job_spec.rb` (local equivalent ran:
  `ruby tmp/self_tests/h5_sla_check_test.rb` → ALL PASS 12)
- H6: `bundle exec rspec spec/services/patra/webhook_emitter_spec.rb` (local equivalent ran:
  `ruby tmp/self_tests/h6_webhook_emitter_test.rb` → ALL PASS 17)
- H7: `bundle exec rspec spec/services/games/asp_net_panel/base_client_redirect_spec.rb`
  (local equivalent ran: `ruby tmp/self_tests/h7_redirect_follow_test.rb` → ALL PASS 9)
  + MORNING SHELL: `bundle exec rails runner script/patra_panda_probe.rb` (the deciding artifact)
- H8: `bundle exec rspec spec/jobs/patra/refresh_fb_tokens_job_spec.rb` (local equivalent ran:
  `ruby tmp/self_tests/h8_fb_token_alert_test.rb` → ALL PASS 12)
- H9: `bundle exec rspec spec/jobs/pending_payment_timeout_job_spec.rb` (local equivalent ran:
  `ruby tmp/self_tests/h9_stuck_pending_alert_test.rb` → ALL PASS 10)
- H10: `bundle exec rspec spec/jobs/ai/reply_job_lock_spec.rb` (local equivalent ran:
  `ruby tmp/self_tests/h10_reply_job_lock_test.rb` → ALL PASS 10)
- H11: `bundle exec rspec spec/services/reengagement/contact_cooldown_spec.rb` (local
  equivalent ran: `ruby tmp/self_tests/h11_shared_cooldown_test.rb` → ALL PASS 12)
- H12: `bundle exec rspec spec/controllers/api/v1/accounts/patra/money_action_guard_spec.rb`
  (local equivalent ran: `ruby tmp/self_tests/h12_money_guard_test.rb` → ALL PASS 5)
- H13: `bundle exec rspec spec/requests/legal_pages_spec.rb` (no local equivalent — needs
  Rails routing; views/layout verified by read, erb comments are non-rendering)

## COMMITS (newest first; rollback = 3a46f24e4)
- e8cd15af1 H13 legal pages verified live — OPERATOR-CONFIRM markers, landing footer links, route spec
- fd6c44e59 H12 PATRA_RESTRICT_MONEY_ACTIONS dark flag (default OFF)
- fca35c7c8 H11 shared reengage cooldown verified, default 72h, sender map
- 54e1ad935 H10 ReplyJob lock release on any error
- c461492e5 H9 stuck-pending sweeper verified + per-conversation rescue
- e936a103a H8 FB token expiry alerting (1/token/day)
- 5f88f75cd H7 asp-net redirect handling + panda probe script
- 95ac8230a H6 Patra::WebhookEmitter (4 events, async)
- 5785cb276 H1 / 3c2f5ed5c H2 / 3b64d09c8 H3 / a5cf0a9ed H4 / 54eac5f90 H5
- 899992acd log init (rollback hash + phase-0 read report)

## FINAL SELF-AUDIT (verified by me at end of run, 2026-06-10)
- ruby -c: 41 touched .rb files, 0 failures (single sweep over `git diff --name-only
  3a46f24e4..HEAD`).
- Self-tests: 12/12 ALL PASS, 221 asserts total (h1:10 h2:21 h3:13 h4:90 h5:12 h6:17 h7:9
  h8:12 h9:10 h10:10 h11:12 h12:5) — each loads the REAL edited file(s) with stubbed Rails.
- Lane proof: diff vs rollback hash contains ZERO hot files (reply_service.rb,
  conversation_orchestrator.rb, intent_detector.rb, chatwoot_bridge_service.rb) and ZERO
  owner-WIP files (telegram_notifier.rb, winback_service.rb, base_provider.rb,
  outbound_dispatcher.rb, zernio_provider.rb). The 7 proof scripts: untouched (no
  script/patra_*.rb in the diff except NEW script/patra_panda_probe.rb, additive).
- RSpec: SPECS-UNRUN locally (bundler exit 127) — 14 spec files written; exact Render
  commands in MORNING SUMMARY + SPECS-UNRUN sections.
- NOT pushed. 14 commits sit on local main on top of 3a46f24e4.
