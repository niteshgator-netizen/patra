# PATRA BACKUP PAGES / CONNECTORS AUDIT — TAB A (2026-06-10 overnight, AUDIT-ONLY)

All load-bearing claims re-verified by TAB A directly (not just sub-agent output). Nothing
changed in these files tonight — they are TAB B lane (jobs + non-games services); exact
diffs are in PATRA_OVERNIGHT_RUN_LOG.md HANDOFF-B-4/5/6.

## What EXISTS today
- **BackupPage model** (app/models/backup_page.rb): platform, page_id, page_name,
  access_token (never serialized out), status standby/warming/active/banned/retired,
  position, health_check_at, stats jsonb; promote!/mark_banned!.
- **UI**: PatraBackupPages.vue (admin-only route) — add/remove/reorder, status dropdown.
- **Hourly health check** (app/jobs/backup/health_check_job.rb, cron 0 * * * *): Graph
  GET per page, ban codes 190/368 → unhealthy; active page dead → promote next healthy
  backup by position + CustomerMigration + telegram; warming pages advance via DripScheduler.
- **DripScheduler** (app/services/backup/drip_scheduler.rb): warming schedule day 1 →
  responding, 3 → partial_intro, 7 → fully_active → promote!.
- **CustomerMigration** (app/services/backup/customer_migration.rb): on switch, posts a
  "we've moved" message into every contact's last conversation + stamps account attrs.
- **Inbound routing** (chatwoot_bridge_service.rb:429-438): fb_page_id → Channel::Api inbox
  (+ F11 fallback chain). Health indicator on the Games/Channels pages is read-only — the
  game-panel IP whitelist is EXTERNAL; Patra displays health only.

## BUGS FOUND IN THE EXISTING SCAFFOLD (verified by me, file:line)
1. **BUG-6 (HIGH within this feature): ban alerts crash the sweep.**
   health_check_job.rb:64,69 call `Games::TelegramNotifier.notify(page.account, message)` —
   notify is PRIVATE (telegram_notifier.rb:160) and keyword-only (:162). The F2/F3 crash
   class, still live here: first detected ban → NoMethodError → find_each aborts (later
   pages unchecked) → 3 retries re-crash. Promotion/migration side-effects land BEFORE the
   crash, so state mutates but nobody is told. → HANDOFF-B-4 (exact diff in run log).
2. **Warming clock is broken two ways.** drip_scheduler.rb:26-29 derives days_in_warming
   from `updated_at`, but health_check_job.rb:20 `update!(health_check_at:)` touches
   updated_at EVERY HOUR → days ≈ 1 forever → page never advances. AND the lookup
   `WARMING_SCHEDULE[days]` only matches exact days 1/3/7 — day 2 (or any other day) falls
   through `|| values.last` = 'fully_active' → would promote a 2-day-old page. The two bugs
   currently cancel into "stuck at day 1", but fixing either alone exposes the other.
   → HANDOFF-B-5.
3. **CustomerMigration mass-messages every contact** with a plain MessageBuilder message —
   no winback tag, no 24h-window check, no volume cap → guaranteed FB #10 policy errors at
   scale on the NEW page (the F19 class), risking the fresh page immediately. → HANDOFF-B-6
   (recommend: telegram the operator + migrate on-reply only, never blast).

## What a real backup-page drip still NEEDS (gap list)
- Inbox linkage on promotion: promote! flips BackupPage.status but no Channel::Api inbox is
  created/repointed — inbound for the new page only works if an inbox with that fb_page_id
  already exists (FacebookConnectController path). Promotion should create/repoint the inbox.
- Outbound failover: SendApiService/OutboundDispatcher never consult BackupPage on Graph
  190/368 — sends just fail until the hourly health check runs. (F14 alerting exists.)
- Restore path: if the primary gets unbanned there is no demote/restore flow.
- Warming engagement strategy (what actually warms the page) is not implemented — only the
  phase state machine exists.

## VERDICT
Scaffold ≈ half-built and the automated parts have crash/policy bugs. Tonight: nothing
enabled, nothing changed (out of TAB A lane). Safe state: feature only acts if BackupPage
rows exist; recommend operator keeps backup pages at 'standby' until HANDOFF-B-4/5/6 land.
