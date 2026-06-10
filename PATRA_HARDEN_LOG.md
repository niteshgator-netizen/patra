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
- [ ] H6 Patra::WebhookEmitter (4 events, non-hot seams, never blocks money path)
- [ ] H7 panda master blank balance — diagnose + patra_panda_probe.rb
- [ ] H8 FB token expiry alerting (1/token/day idempotent)
- [ ] H9 stuck-pending sweeper alert (verify + spec — alert already exists)
- [ ] H10 ReplyJob rescue posture (lock release on transient, bounded permanent)
- [ ] H11 re-engagement shared cooldown (verify existing + PATRA_REENGAGE_MAP.md + spec)
- [ ] H12 role guards dark flag (PATRA_RESTRICT_MONEY_ACTIONS, default OFF)
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

## COMMITS
(one line per item as committed)
