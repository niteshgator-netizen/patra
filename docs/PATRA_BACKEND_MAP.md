# PATRA BACKEND MAP
Written during launch-night backend pass (TAB B, 2026-06-10). Every claim below
was verified by reading the named file in this run — file paths are the source of truth.

## 30-second orientation
Patra = Chatwoot v4.13 hard fork. Rails + Vue, PostgreSQL (+pgvector), Redis + Sidekiq,
deployed on Render (Web Service + Background Worker). The Patra vertical bolts a
sweepstakes-cashier brain ("Bella") onto Chatwoot conversations: players message via
Facebook/Telegram, Bella detects intent, moves money on game panels through audited
executors, escalates to humans via Telegram groups.

## THE MONEY FLOW (the path that matters)
```
player message
  → webhook (FB bridge /bot REST  |  webhooks/telegram → TelegramEventsJob)
  → Chatwoot conversation/message
  → Ai::ReplyService (HOT, app/services/ai/reply_service.rb)
      └→ Games::ConversationOrchestrator (HOT, app/services/games/conversation_orchestrator.rb)
          ├─ Games::IntentDetector (HOT) regex first; RAG cutover when regex nil
          ├─ fraud guards: cashout_velocity_state, recent_cashout_duplicate?,
          │                duplicate_recent_load? (all in orchestrator, DB-backed via GameAction)
          ├─ money handlers: handle_load_intent, handle_cashout_intent,
          │   handle_transfer_between_games (forks: normal_cashout / deposit_only /
          │   shortfall refuse|transfer_available / whole),
          │   handle_redeem_partial_replay, handle_new_account_reissue,
          │   handle_replay_from_balance (read-only)
          └→ Games::ActionExecutor (NON-hot, app/services/games/action_executor.rb)
              ├─ audit: every action = a GameAction row (order_id unique per account = idempotency)
              ├─ guards: blacklist, per-panel max_load/max_cashout creds,
              │          Approvals::CashoutApprovalGate (approval_required short-circuit)
              ├─ [MONEY] structured log line per result (added tonight)
              └→ Games::ClientRegistry.client_for(agent_game) → panel client
```

### Panel client families (app/services/games/)
| Family | Clients | Auth | Quirks |
|---|---|---|---|
| GameVault | game_vault, vegas_sweeps (subclass) | MD5(agent:ts:secret) | SHARED player namespace; already-exists code **20** → executor verifies + reuses |
| Juwa | juwa, juwa2 | MD5 token | user_id resolved via getUserID; addUser verification net |
| FastAPI | fast_api base → vblink, ultra_panda (siblings) | appid+timestamp+MD5 sign | already-exists code **12** (NOT 20 = password error); code 7 = account format (underscores rejected); requestid stripped to alphanumerics |
| ASP.NET (Cluster 1) | asp_net_panel/base_client → milky_way, fire_kirin, panda_master, orion_stars | ASP.NET_SessionId cookie | VIEWSTATE scrape dances; whole-dollar amounts only; reactive session refresh via SessionRefresher (CapSolver) with pg row lock; user_id = "uid:gid" |
| Laravel (Cluster 2) | mafia, game_room, cash_machine, mr_all_in_one | JWT bearer + cookie | |

All clients implement the universal interface: agent_balance, user_balance, get_user_id,
add_user, recharge, withdraw, reset_player_password, force_player_offline, test_connection.
Typed errors: GameVaultError / JuwaError / FastApiError / Games::ClientError — ActionExecutor
rescues all four into `{ok:false, error:, code:, action:}` (never nil).

### Panel failover (AgentGame model)
- record_failure! / reset_failures!: 5 failures in 1h auto-disables (legacy path)
- record_api_failure! / record_api_success!: 3 consecutive → status 'degraded' + one
  Telegram alert; success resets count, degraded stays until human review.
  Orchestrator wires this via record_api_result after every executor call.

## PAYMENTS / VERIFICATION
- PaymentHandle (model): per-account cashapp/chime/paypal/... handles, priority,
  cooldown, max per platform. Payments::HandleSelector picks active.
- Payments::ImapCheckJob + SingleContactImapJob (queue low): poll verification email
  inboxes for payment receipts. Lock-key guarded; in-job 30s backoff on IMAP rate limit.
- Payments::AnnounceVerifiedPaymentJob: tells the player "verified, where to load?" and
  stamps conversation.additional_attributes awaiting_load_amount/set_at (load-on-answer
  picks this up in the orchestrator). Duplicate-enqueue guard added tonight.
- Payments::HandleHealthMonitor: <50% confirm rate in 24h → handle disabled + Telegram
  (fixed tonight: was calling a private method → NoMethodError; now api_error; skips
  already-disabled).
- PendingPaymentTimeoutJob: read-only sweep for stale pending payments.
- Ai::ImagePaymentExtractor: Gemini 2.5 Flash vision on payment screenshots →
  {is_payment, platform, amount, sender_name, ...}; never raises (safe error hashes).

## AI FLOWS
- Ai::DeepseekClient (app/services/ai/deepseek_client.rb): THE shared LLM caller.
  content → reasoning_content fallback, returns nil on any failure, single retry on
  5xx/timeout (added tonight). Model const deepseek-v4-flash.
- Ai::ReplyService (HOT, ~2.7k lines): Bella's brain. build_system_prompt assembles
  persona/payment/rules/RAG; DEEPSEEK_MODEL env read at line ~2141.
- RAG: BellaRagPair (73k rows, account 2), IntentRetriever.predict/retrieve,
  RAG_TO_INTENT_MAP in orchestrator (cutover confidence 0.40). ALL TAB-A territory.
- Fleet (non-hot, app/services/ai/): copilot_service (→ DeepSeek as of tonight; was a
  dead OpenAI path), smart_compose, tag_suggester, conversation_summary_service,
  sentiment_scorer + complexity_classifier (pure regex/keyword), vault_context_builder
  (reads game_username_<slug>/game_password_<slug> contact attrs),
  player_memory_writer (folds old messages into patra_player_memory, summary capped 4000
  chars) + RotatePlayerMemoryJob (1000 unsummarized triggers folding oldest 500),
  business_hours_checker + enhanced (+Holiday model), playground_prompt_builder (new).
- Live-AI endpoints (new tonight): PatraAiAnalysisController (per-conversation strict-JSON
  analysis → conversation.custom_attributes['patra_ai_analysis']),
  PatraPlaygroundController (persona test bench, no persistence).
- Win-back (games/winback_service.rb + winback_job): dormant players diagnosed by
  DeepSeek; ≤7d → winback-flagged outgoing message (HUMAN_AGENT tag path), >7d →
  Telegram manual-send + private note. Idempotent via winback_last_contacted_at +
  Reengagement::ContactCooldown.

## FACEBOOK PIPELINE
- Inbound: /bot REST bridge (chatwoot_bridge_service.rb — HOT) pushes Messenger events
  via the public API (Account 2 / API inbox 5; FacebookPage inbox 2 is BROKEN, unused).
- Outbound: message_created webhook → FbReplyJob → Facebook::SendApiService
  (190-dead-token detection + 1h-throttled Telegram alert) → Messaging::OutboundDispatcher
  → provider (zernio etc.).
- Facebook::PatraGraphService: OAuth/page listing/token exchange. Raises typed
  GraphApiError (fb_code, token_expired?, rate_limited?) as of tonight.
- Facebook::GraphProfileService: name lookups, fails soft to fallback profile.
- Patra::RefreshFbTokensJob: rotates page tokens, age-guarded, rescues everything.
- BackupPage model: standby pages for ban recovery (access_token JSON-redacted tonight).

## TELEGRAM (ops nervous system)
- Outbound alerts: Games::TelegramNotifier (owner-WIP — read only). Public API:
  cashout_alert, load_alert/load_failed, human_escalation, api_error, low_balance_alert,
  winback_manual_alert, claim_available, shift_report... `notify` itself is PRIVATE.
  Cashout group -5243223053. Everything wrapped via safe_telegram blocks in callers.
- Inbound: webhooks/telegram/:bot_token → TelegramEventsJob (update_id dedup via Redis
  as of tonight) → Telegram::IncomingMessageService. Webhook secret validation added
  tonight: HMAC(secret_key_base, bot_token) registered at setWebhook, header checked,
  enforcement opt-in via TELEGRAM_WEBHOOK_VALIDATE_SECRET.

## CASHIER OPS
- CashierClaim: pending work queue (load/cashout), 5-min expiry, claim!/complete! by
  agents (deliberately not admin-gated), CashierClaimsController scoped + tenant-checked.
- Patra::IncidentController (admin-only as of tonight): pause_ai, broadcast_open,
  reassign_all.
- Referral + ReplyPreference referral_* fields: referral bonuses; settings admin-gated
  tonight; self-referral blocked at model tonight.
- PlayerTier (regular/vip/selected/new_player/blocked) + GameRule per account+game
  (freeplay/deposit-bonus/cashout rules — cashout_min_amount drives the transfer fork).
- AgentShift, PlayerBonus: shift tracking + manual comps.

## DATA MODEL (Patra tables; NOTE db/schema.rb is STALE — read db/migrate/*)
games, agent_games (credentials JSONB encrypted), game_actions (audit log + idempotency),
game_rules, player_tiers (+contacts.player_tier_id), player_bonuses, referrals,
reply_preferences (1/account: tone, rag, transfer_mode, fraud_*, winback_*, referral_*),
cashier_claims, backup_pages, holidays, payment_handles.
Contact.custom_attributes carries: game_username_<slug>/game_password_<slug>,
patra_finance_logs[], patra_player_memory{}, winback_last_contacted_at,
last_deposit_amount/method, preferred_platform, activity_score, lifecycle_stage.
Conversation.additional_attributes: awaiting_load_amount/set_at, pinned;
custom_attributes: ai_summary, patra_ai_analysis.

## JOBS BY QUEUE
- default: TelegramEventsJob, AnnounceVerifiedPaymentJob
- low: ImapCheckJob, SingleContactImapJob, PendingPaymentTimeoutJob,
  HandleHealthMonitorJob, RotatePlayerMemoryJob, RefreshFbTokensJob,
  ProactiveSessionRefreshJob (pg-row-lock guarded)

## HOT FILES (edit only with extreme care, one per change)
1. app/services/ai/reply_service.rb
2. app/services/games/conversation_orchestrator.rb
3. app/services/games/intent_detector.rb
4. app/services/facebook/chatwoot_bridge_service.rb

## OPS SCRIPTS
- script/patra_launch_readiness.rb — env presence + live pings + readiness checks
- script/patra_data_integrity.rb — read-only data sweep (new tonight)
- script/patra_reply_smoke.rb — reply-path smoke

## SECURITY POSTURE (after tonight)
- All custom API controllers authenticated + Current.account-scoped (TEN audit table in
  PATRA_LAUNCH_LOG.md). Admin gates on incident/backup-page/referral-settings mutations.
- Telegram webhook secret validation (opt-in), rack_attack throttles on webhook +
  live-AI + claim endpoints, Sentry key-scrub for message bodies/secrets.
- Secrets: see SECRETS_ROTATION_RUNBOOK.md — telegram token + juwa secret confirmed in
  git history, rotation mandatory.
