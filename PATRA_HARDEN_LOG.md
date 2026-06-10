# PATRA HARDENING RUN LOG — 2026-06-10

## ROLLBACK HASH (state before this run)
```
3a46f24e411be564b3e821ea201e290c60cb9e4c
```
To roll back everything from this run: `git reset --hard 3a46f24e411be564b3e821ea201e290c60cb9e4c`

## MORNING SUMMARY
(written last — see bottom-up progress in QUEUE)

## QUEUE
- [ ] H1 backup ban-alert crash (health_check_job.rb per-page rescue + public api_error)
- [ ] H2 warming clock (drip_scheduler.rb warming_started_at stamp + phase floor + day-7 gate)
- [ ] H3 customer-migration mass-blast → operator alert + 24h-window capped notes
- [ ] H4 dead crons (.rb-suffixed names) + full cron audit
- [ ] H5 SLA wiring (sla_alerts_enabled / first_response / resolution mirrors)
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
(collected per item)

## COMMITS
(one line per item as committed)
