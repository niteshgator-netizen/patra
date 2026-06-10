# PATRA HARDENING RUN LOG — 2026-06-10

## ROLLBACK HASH (state before this run)
```
3a46f24e411be564b3e821ea201e290c60cb9e4c
```
To roll back everything from this run: `git reset --hard 3a46f24e411be564b3e821ea201e290c60cb9e4c`

## MORNING SUMMARY
(written last — see bottom-up progress in QUEUE)

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
- [ ] H13 terms/privacy pages (already exist — verify + OPERATOR-CONFIRM markers)
- [ ] FINAL self-audit + DUMP

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
- D0b: Local probe of panel endpoints attempted (read-only GETs) — both panda AND orion return
  HTTP 500 NullRef pages to non-session traffic from this machine, so the 301-vs-200 difference is
  only observable with real session cookies → Render probe script is the deciding artifact.

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

## COMMITS
(one line per item as committed)
