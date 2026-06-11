# PATRA MEGA RUN 2 — FULL LOG (2026-06-11)

ROLLBACK=665b6985de6b9f71e15ab0918f805af137e1bc97
Revert (newest first): 9bcbc6e3c, b15dd481a, 1e9c34b78, be8cf69a7, c0de4f186,
abcc33649, 5d815f639, 689e3efeb, c9097ef31, 85ee14f7a, 8431e3cd6, c3917caa4,
0ba4c93ff, db353c49e, 498114887 (+ the docs commit after this file).

NOT pushed. NOT deployed. No prod-DB access during the run.

---

## PHASE 0 — FACTS (verified in code, file:line)

1. `handle_cashout_intent` orchestrator:1157-1325; over-max branch :1259 →
   `handle_over_max_cashout`; pre-run both modes moved NO money (cashier-manual)
   and only changed wording. `cashout_overmax_mode_pref` read ReplyPreference
   column → account custom_attributes → default `cash_whole`; no `ask_first`,
   unknown values silently defaulted.
2. `link_referred_on_account_creation` orchestrator:4473-4489 linked the NEWEST
   account-wide pending Referral (referred_contact_id nil) to ANY account
   creator. Callers :1540/:1639/:1676 (account-creation paths).
   `escalation_context` :4448 builds the 5-part ' | ' string.
3. reply_service.rb:835 bare `reason: reply.to_s[0..200]` escalation.
4. Referral columns: account_id, referrer_contact_id (NN), referred_contact_id
   (nullable), status, bonus_amount, bonus_type, paid_at. NO conversation_id /
   metadata → only deterministic linkage is referred_contact_id.
   `link_referred` sets verified + `check_and_pay` (gated on referral_enabled,
   default false → nothing auto-pays).
5. Inbound Telegram: routes.rb:763 webhooks/telegram/:bot_token is for
   Channel::Telegram inboxes; secret enforcement dark unless
   TELEGRAM_WEBHOOK_VALIDATE_SECRET=true. The OPS bot (TELEGRAM_BOT_TOKEN +
   TELEGRAM_CASHOUT_GROUP_ID) was outbound-only — no inbound webhook existed.
6. ApprovalRequest: statuses pending/approved/rejected; approve!/reject!;
   after_update_commit → Approvals::AutoResumeJob when
   PATRA_APPROVAL_AUTORESUME=true (shipped dark). Execute method:
   `Approvals::AutoResume.execute!(approval)` — exactly-once via order_id
   `appr_<id>` on game_actions(account_id, order_id) unique index. AutoResume
   notify texts printed approval ids; orchestrator human_escalation texts did NOT.
7. freeplay_auto decision: orchestrator:629-650 (override approve/deny;
   unconfigured default escalates). Deposit history source: GameAction
   load/success with `COALESCE(metadata->>'freeplay','false') != 'true'`.
   patra_finance_logs = JSONB array on contacts.custom_attributes (no table).
8. games/laravel_panel/base_client.rb JSON.parse sites: :66 agent_balance
   (read, pre-write), :103 add_player (after write), :153 reset (after write),
   :174 post_action (after agentRecharge/agentWithdraw — the MONEY sites).
   Parse failure propagated as a raw JSON::ParserError → executor marked the
   action plain 'failed' even though the panel may have executed.
9. Schema: unique game_actions(account_id, order_id);
   conversations(account_id, display_id) + uuid. Hairtriggers:
   conversation.rb:341 (conv_dpid_seq_<account>), campaign.rb:128
   (camp_dpid_seq_<account>). game_actions NN: account_id, agent_game_id,
   action_type, order_id, status. approval_requests NN: account_id,
   requesting_user_id, action_type, status.
10. ReplyJob: bounded retries (3/5) + lock release on error (good); GAP: a
    raise in log_to_chatwoot AFTER a successful FB send re-raised into a retry
    → double-send window; give-up was log-only. Re-engage/dormant/winback share
    Reengagement::ContactCooldown ('last_automated_contact_at', 72h default,
    ENV PATRA_REENGAGE_COOLDOWN_HOURS); Drip::ProcessCampaignJob did NOT check
    or stamp it and sent with zero stagger.
11. Player Vault: UIs build cards from game_username_<slug> +
    REQUIRE game_password_<slug>; cursor badges read vault_cursor_msg_id
    (PlayerProfileCard.vue:411) / vault_cursor_id (ContactDetails.vue:113);
    backend wrote only player_vault_cursor_message_id (profile_service.rb:9) —
    confirmed key mismatch, UI cursor keys never written.
12. June-10 leftovers: (a) "crashing crons" were name-malformed labels; drip +
    email-poll have per-record rescues — FIXED earlier. (b) freshness gate —
    FIXED earlier (real @latest_timestamp, reply_service:340). (c) add_player
    verification net PRESENT (action_executor.rb:236 player_exists_after_create?,
    wired :49-77, covers Juwa via get_user_id). (d) FB signature enforcement
    implemented but DARK: 401 only when PATRA_ENFORCE_WEBHOOK_SIGNATURE=true;
    needs FB_APP_SECRET (ENV or GlobalConfig); verifier + log-only Redis
    counter already in place (bot_controller.rb:76-103).
13. FB tokens: weekly Patra::RefreshFbTokensJob refreshes Channel::Api inboxes
    with fb_page_id; no daily validation existed. Graph code 190 = dead token.
14. payment_info_builder.rb best_handle = min_by [failure_count, priority];
    payment_handles has failure_count + last_failure_at; NO decay existed.

## PHASES — what/why/files/commit

| Phase | Commit | Files | What |
|---|---|---|---|
| P1 referral hijack [HOT] | 498114887 | conversation_orchestrator.rb | Link only when exactly ONE pending referral already references this contact; otherwise leave pending + escalate 5-part once per contact (escalated-ids stamp). Zero pendings = no-op. referral_enabled stays the pay switch. |
| P2 escalation format [HOT] | db353c49e | reply_service.rb | :835 one-liner → full 5-part ' \| ' format (PLAYER WANTS / ALREADY DONE / STILL LEFT / BELLA SUGGESTS / NEEDS FROM HUMAN). |
| P3 over-max modes [HOT] | 0ba4c93ff | conversation_orchestrator.rb | cashout_overmax_mode setting: cash_whole (default = today's no-money behavior, reply now states the math plainly), pay_max_recharge (Bella runs in-game redeem + recharge legs, payout stays cashier-manual; recharge failure escalates real state, never retried; dedup + deterministic ovmx_<action> order_id), ask_first (no money, held pending_overmax_choice on conversation, 30-min stale-out, answer routes to the other two; no reply → nothing moves). Unknown mode → warn log + cash_whole. |
| P4a Telegram two-way | c3917caa4 | telegram_ops/command_handler.rb, command_job.rb, patra_telegram_ops_controller.rb, routes.rb, script/patra_telegram_commands_check.rb | 'approve <id>' / 'deny <id>' from ANY member of TELEGRAM_CASHOUT_GROUP_ID; same execute path as dashboard/AutoResume; group reply with real result; unknown/already/malformed/chatter/double-approve handled; update_id dedup. ALL DARK behind PATRA_TELEGRAM_COMMANDS='true'. |
| P4b approval ids [HOT] | 8431e3cd6 | conversation_orchestrator.rb | approval_ref_text helper; freeplay/bonus/referral/over-threshold escalations now print "approval #N: reply 'approve N' or 'deny N'" (added at call sites, NOT in telegram_notifier). |
| P5 freeplay-farm guard [HOT] | 85ee14f7a | conversation_orchestrator.rb | Any auto freeplay grant requires >= freeplay_min_deposits (default 1; 0 disables) confirmed real deposits ever; fail → 5-part escalation, no grant. Count fails CLOSED (0). |
| P6a Laravel ambiguous | c9097ef31 | client_error.rb, laravel_panel/base_client.rb, action_executor.rb | Games::AmbiguousPanelStateError raised on parse failure AFTER a write (:103/:153/:174); executor marks status='ambiguous' + metadata.ambiguous=true, escalates "panel MAY have credited — verify before any redo", never auto-retries. :66 (read) stays a plain failure (nothing written yet). |
| P6b ambiguous blocks F12 [HOT] | 689e3efeb | conversation_orchestrator.rb | deterministic_payment_order_id treats 'ambiguous' like success/pending → automatic re-execution of that payment blocked. |
| P7 DB probe | 5d815f639 | script/patra_db_integrity_check.rb | Report-only: hairtriggers, unique indexes, NOT NULLs, serial sequence health (behind-sequence flag), FKs. Zero writes. |
| P8 wiring audit | (report-only, below) | — | No code changes. |
| P9 nudge cooldown + stagger | abcc33649 | process_campaign_job.rb, flow_executor.rb, re_engage_job.rb | Drip now checks AND stamps the shared Reengagement::ContactCooldown key (single key across re-engage/dormant/winback/drip; 72h default ≥ the 24h requirement); stamps only when a message actually went out (FlowExecutor#sent_any_message?); 0.5-2.5s jitter between sends in drip + re-engage. winback_service untouched (OWNER-WIP) — verified read-only that it already honors the shared key (:70 check, :311 stamp). |
| P10 stuck sweeper | c0de4f186 | patra/stuck_pending_sweeper_job.rb, schedule.yml | Every 15 min; pending approvals + pending game actions older than PATRA_STUCK_MINUTES (default 30) → ONE grouped 5-part alert, max once/hour (Redis stamp), never acts. |
| P11 FB token health | be8cf69a7 | patra/fb_token_health_job.rb, schedule.yml | Daily 0410 UTC; cheapest Graph call per page token; dead (190/401) / missing / >53d-old → 5-part alert naming inbox+page; per-token rescue; unreachable Graph = no verdict, no false alarm. Read-only. |
| P12 ReplyJob posture | 1e9c34b78 | ai/reply_job.rb | Double-send guard: post-send log_to_chatwoot failures no longer re-raise into a retry (main + blacklist paths); retry give-up now Telegrams the group. |
| P13 handle decay | b15dd481a | bella/payment_info_builder.rb | failure_count resets to 0 lazily on the picker read path when last_failure_at older than handle_decay_days (default 7; 0 disables); each decay logged; undatable failures (no last_failure_at) left alone. |
| P14 vault writer | 9bcbc6e3c | players/profile_service.rb | Backend now writes vault_cursor_msg_id + vault_cursor_id (the keys the two Vault UIs read) alongside the legacy idempotency key (renaming the legacy key would re-backfill and double-count deposit totals). |
| P15 leftovers | (verify-only) | — | See status lines below. |

## NEW SETTINGS / ENV — safe defaults

| Setting | Where | Default | Effect of default |
|---|---|---|---|
| PATRA_TELEGRAM_COMMANDS | ENV | unset (OFF) | inbound commands fully dark; webhook acks + drops |
| PATRA_TELEGRAM_OPS_WEBHOOK_SECRET | ENV | unset | secret check dark (warn-log only) |
| cashout_overmax_mode | account custom_attributes | cash_whole | today's behavior; reply now states the math plainly |
| freeplay_min_deposits | account custom_attributes | 1 | blocks zero-deposit farmers only; freeplay_auto unconfigured everywhere today (escalates), so prod outcome unchanged |
| PATRA_STUCK_MINUTES | ENV | 30 | sweeper age threshold (alert-only job) |
| handle_decay_days | account custom_attributes | 7 | failure_count decays after 7 quiet days; 0 disables |

## EDGE-CASE TABLE (money phases)

| Case | Behavior |
|---|---|
| P1 zero pending referrals | no-op, no escalation |
| P1 multiple pendings referencing this contact | never guess → escalate, nothing linked |
| P1 re-run same contact | deterministic: linked referral leaves 'pending' → no double-link; ambiguous: escalated-ids stamp → no double-escalate |
| P1 referral_enabled false (default) | link sets 'verified' only; check_and_pay exits → nothing auto-pays |
| P3 cash_whole | no panel calls (today's behavior), reply states "$max paid, $leftover doesn't carry" |
| P3 pay_max_recharge redeem fails | NOTHING moved, 5-part escalation, no retry |
| P3 pay_max_recharge recharge fails | redeem done; escalation states real state ($leftover out of game, $max owed); NEVER auto-retried |
| P3 pay_max_recharge duplicate | recent_cashout_duplicate? window (120s) skips; recharge leg idempotent via ovmx_<redeem-action-id> order_id |
| P3 ask_first no reply | nothing moves; flag stales out after 30 min |
| P3 ask_first re-ask while pending | re-asks player, does NOT re-escalate |
| P3 ask_first ambiguous answer (both options matched) | falls through, nothing moves |
| P3 unknown mode value | warn log + cash_whole |
| P4 unknown id / already resolved / malformed / chatter | group reply / "already X - no-op" / usage hint / silent ignore |
| P4 double-approve race | both approve; execution collapses on appr_<id> unique index; second reply "already executed - no double-move" |
| P4 AutoResume disabled | approve marks the record; group told "auto-execute is OFF, execute manually" (the real state) |
| P4 Telegram redelivers an update | update_id Redis dedup (24h) → ignored |
| P5 deposit count query fails | fails CLOSED (counts 0 → no grant, escalation) |
| P5 freeplay_min_deposits=0 | guard fully disabled |
| P6 parse failure after money write | status 'ambiguous' (not failed), metadata.ambiguous=true, 5-part "panel MAY have credited", no auto-retry; F12 blocks re-execution of the same payment |
| P6 parse failure on agent_balance (read) | plain failure — nothing was written |
| P10 nothing stuck | no alert; alert at most once/hour when stuck records exist |
| P12 log-to-chatwoot fails after FB send | logged loudly, NO retry → no double-send |
| P13 failure with no last_failure_at | left alone (cannot date it) |

## P8 — UI↔BACKEND WIRING AUDIT (report-only)

All reply-preference fields exposed on Settings → ReplyStyle and
Settings → AutomationSafety are WIRED (endpoint + UI). referral_* columns live
in reply_preferences but are wired through the separate
/referrals/settings endpoint (referrals/Index.vue) — wired, just split.
No UI-ORPHANS found (every UI call has a route).

NO-UI endpoints (money-relevant): approval_requests index/approve/reject
(api/v1/accounts/approval_requests_controller.rb) have routes but ZERO
frontend callers — approvals are operated via Telegram alerts (and now
'approve <id>' commands), not the dashboard.

Where each operator setting is set today:

| Setting | Where set today |
|---|---|
| cashout_overmax_mode | shell: account custom_attributes (no UI) |
| freeplay_min_deposits | shell: account custom_attributes (no UI) |
| handle_decay_days | shell: account custom_attributes (no UI) |
| freeplay_auto / bonus_percent_override | shell: contact custom_attributes (no UI) |
| freeplay_amount | Settings → Game Rules (per game) — wired |
| freeplay_daily_limit_per_player, bonus_percent, first_deposit_bonus_percent, bonus_min_deposit, referral_percent, referral_fixed_amount, referral_reward_mode, referral_min_deposit | shell: account custom_attributes (no UI) |
| reengage_days / reengage_message | PatraBusinessSettings.vue — wired |
| transfer_mode, auto_load_threshold, fraud_* | Settings → AutomationSafety — wired |

Also noted (P14-adjacent, report-only): both Vault UIs hide a game card unless
game_password_<slug> exists; loads that store a player-provided username never
store a password, so those games can't show in the vault. Backend cannot
invent the password — needs a product decision (UI change or password capture).

## P15 — LEFTOVER STATUS LINES

- (a) crashing crons: VERIFIED already fixed — drip (process_campaign_job.rb:23)
  and email poll (email_poll_job.rb:33) have per-record rescues; the two ".rb"
  cron entries were label-name cosmetics, classes resolvable. No change made.
- (b) freshness gate: VERIFIED already fixed — reply_service.rb:340 gate +
  real @latest_timestamp capture (:1336). Fires correctly. No change made.
- (c) Juwa add_player verification net: VERIFIED present —
  action_executor.rb:236 player_exists_after_create? wired into add_player
  (:49-77) for all clients incl. Juwa (silent_fail path escalates). No change made.
- (d) FB webhook signature: implemented, DARK. Flipping
  PATRA_ENFORCE_WEBHOOK_SIGNATURE=true requires FB_APP_SECRET present (ENV or
  GlobalConfig); check the log-only counter
  patra:webhook:invalid_signature:YYYYMMDD for a quiet week first.

## OPERATOR RUNBOOK

- Telegram commands ON: set PATRA_TELEGRAM_COMMANDS=true on Render; register
  the ops-bot webhook:
  `https://api.telegram.org/bot<TELEGRAM_BOT_TOKEN>/setWebhook?url=https://patrahq.com/webhooks/patra_telegram_ops&secret_token=<PATRA_TELEGRAM_OPS_WEBHOOK_SECRET>`
  then verify: `bundle exec rails runner script/patra_telegram_commands_check.rb`
  For approve to also EXECUTE, PATRA_APPROVAL_AUTORESUME=true must be set.
- Over-max mode: `Account.find(2).then { |a| a.update(custom_attributes: (a.custom_attributes||{}).merge('cashout_overmax_mode' => 'ask_first')) }` (values: cash_whole | pay_max_recharge | ask_first).
- Freeplay guard: same pattern with 'freeplay_min_deposits' => 2 (0 disables).
- Handle decay: same pattern with 'handle_decay_days' => 14 (0 disables).
- Sweeper age: PATRA_STUCK_MINUTES=45 on Render (alert-only either way).
- DB probe: `bundle exec rails runner script/patra_db_integrity_check.rb`
  (zero writes; run on Render shell).

## SELF-AUDIT RESULTS

- ruby -c on every touched .rb: ALL Syntax OK. schedule.yml: YAML OK.
- Zero edits to BOUNDS files (verified by diff grep): no app/javascript, no
  CSS/SCSS/Vue, no intent_detector, no telegram_notifier.rb, no
  winback_service.rb, no base_provider/outbound_dispatcher/zernio_provider,
  no public/vite, no public/packs.
- script/patra_money_harness.rb untouched.
- grep diff for TODO/stub/placeholder: zero.
- 15 phase commits, all [MEGA2]-prefixed, one hot-file change per commit
  (orchestrator commits: P1, P3, P4b, P5, P6b; reply_service: P2).
- Per-file change size: orchestrator +385/-25 (~8% of 4.6k lines across 5
  commits), reply_service +6/-1 (<0.3%), everything else new files or <45 lines.
