# PATRA — BUGS FIXED LEDGER

**FILTER APPLIED:** commits since 2026-05-01 only (Patra era, excludes inherited Chatwoot history)
**Author breakdown:** genius (369), Sivin Varghese (7), Aakash Bakhle (5), Muhsin Keloth (5), Vishnu Narayanan (4)
**Date range in ledger:** 2026-05-04 → 2026-05-31

Source: git log (ground truth). Auto-generated 2026-05-31.
Total commits scanned: 408
Fix commits found: 131

## CONVENTIONS
- F-XXX = sequential ID
- Date = commit author date
- Hash = short commit SHA (clickable in GitHub)
- Files = top 3 files changed (or "+N more")

---

## FIX COMMITS (commits starting with fix:, bug:, hotfix:, or containing "fix ", "fixed ", "bug ", "crash", "broken", "regression" in subject)

### F-001 | 2a30e7b08 | 2026-05-04
**Author:** Sivin Varghese
**Subject:** fix: render agent variables in automation messages (#14338)
**Files changed:** app/drops/user_drop.rb, app/models/concerns/liquidable.rb
**Body excerpt (if exists):** ## Description This PR fixes an issue where agent variables like `{{agent.name}}`,`{{agent.first_name}}`, `{{agent.last_name}}`, and `{{agent.email}}` were not rendering in automation messages. In aut

### F-002 | a01adf860 | 2026-05-04
**Author:** Pranav
**Subject:** fix: [CW-7001] Limit emails fetch (#14354)
**Files changed:** app/services/imap/base_fetch_email_service.rb, spec/services/imap/fetch_email_service_spec.rb
**Body excerpt (if exists):** expensive/long-running mailbox scans. It also filters out already-imported emails and Chatwoot-generated notification emails during the header fetch phase, before fetching full email bodies, reducing 

### F-003 | d00867d63 | 2026-05-04
**Author:** Aakash Bakhle
**Subject:** fix: captain auto sync scheduler config (#14336)
**Files changed:** app/jobs/internal/trigger_hourly_scheduled_items_job.rb, config/initializers/sidekiq.rb, config/installation_config.yml [+7 more]
**Body excerpt (if exists):** none

### F-004 | 2dee7457c | 2026-05-04
**Author:** Vishnu Narayanan
**Subject:** fix: set minimal top-level permissions on workflows (#14358)
**Files changed:** .github/workflows/deploy_check.yml, .github/workflows/frontend-fe.yml, .github/workflows/logging_percentage_check.yml [+6 more]
**Body excerpt (if exists):** workflow level. The codespace image publish workflow additionally needs packages: write to push to ghcr.io.

### F-005 | 6386eec5e | 2026-05-05
**Author:** Sivin Varghese
**Subject:** fix: regex validation not applied for custom text attributes in UI (#14110)
**Files changed:** app/javascript/dashboard/components-next/CustomAttributes/OtherAttribute.vue, app/javascript/dashboard/components/CustomAttribute.vue, app/javascript/dashboard/routes/dashboard/settings/attributes/AddAttribute.vue [+4 more]
**Body excerpt (if exists):** ## Description This PR fixes multiple issues related to regex patterns and validation for custom attributes. 1. Fixed regex patterns being double-escaped when saving from Add and Edit flows 2. Fixed r

### F-006 | c1d167bd6 | 2026-05-05
**Author:** Sivin Varghese
**Subject:** fix: prevent `--` signature delimiter rendering as `\` in bubble (#14134)
**Files changed:** app/javascript/dashboard/helper/editorHelper.js, app/javascript/dashboard/helper/specs/editorHelper.spec.js, app/javascript/shared/helpers/MessageFormatter.js [+1 more]
**Body excerpt (if exists):** ## Description Fixes https://linear.app/chatwoot/issue/CW-6903/signature-delimiter-renders-as-h2-when-using-enter-line-before **1**. Fixes an issue where the signature delimiter `--` gets parsed as an

### F-007 | a9ac1c633 | 2026-05-05
**Author:** Sony Mathew
**Subject:** fix: added HMAC validation for Whatsapp and Instagram webhooks (#14280)
**Files changed:** app/controllers/concerns/meta_token_verify_concern.rb, app/controllers/webhooks/instagram_controller.rb, app/controllers/webhooks/whatsapp_controller.rb [+3 more]
**Body excerpt (if exists):** * Added Meta webhook HMAC validation in meta_token_verify_concern.rb. * Wired it into instagram_controller.rb and whatsapp_controller.rb. * WhatsApp now verifies X-Hub-Signature-256 with WHATSAPP_APP_

### F-008 | 941c8a86b | 2026-05-05
**Author:** Vishnu Narayanan
**Subject:** fix: use a dedicated PAT for ghsa linear sync gh action (#14364)
**Files changed:** .github/scripts/ghsa_linear_sync.py, .github/workflows/ghsa-linear-sync.yml
**Body excerpt (if exists):** Switched to a fine-grained PAT stored in `GHSA_READ_TOKEN`. Tested locally: the same PAT returns the full triage list Changes ---- - Switch to custom token - Add a discord alert for new advisories - S

### F-009 | 2192af80f | 2026-05-05
**Author:** Vishnu Narayanan
**Subject:** fix: html-escape captured values in helpcenter article markdown embeds (#14140)
**Files changed:** lib/custom_markdown_renderer.rb, spec/lib/custom_markdown_renderer_spec.rb
**Body excerpt (if exists):** URLs into HTML attribute values. CommonMark's angle-bracket link destination syntax allows characters that the capture regexes don't filter, so the unescaped substitution could produce malformed attri

### F-010 | 8d7e926e0 | 2026-05-06
**Author:** Sojan Jose
**Subject:** fix: [Snyk] Security upgrade video.js from 7.18.1 to 7.21.1 (#13973)
**Files changed:** package.json, pnpm-lock.yaml
**Body excerpt (if exists):** ### Snyk has created this PR to fix 1 vulnerabilities in the yarn dependencies of this project. #### Snyk changed the following file(s): - `package.json` #### Note for [zero-installs](https://yarnpkg.

### F-011 | d7d1e4113 | 2026-05-06
**Author:** Aakash Bakhle
**Subject:** fix: captain auto sync scheduler resilience (#14379)
**Files changed:** enterprise/app/jobs/captain/documents/schedule_syncs_job.rb, spec/enterprise/jobs/captain/documents/schedule_syncs_job_spec.rb
**Body excerpt (if exists):** ## Description skip documents that fail with ActiveRecord errors possibly due to stale/corrupt data and not crash scheduler How did we find out about this error? before October 28th, 2025, we did not 

### F-012 | 7a7db22a4 | 2026-05-07
**Author:** Cesar Garcia
**Subject:** fix: Implement resend confirmation feature for login page (#11970)
**Files changed:** app/controllers/devise_overrides/sessions_controller.rb, app/javascript/v3/api/auth.js, app/javascript/v3/views/login/Index.vue [+1 more]
**Body excerpt (if exists):** ## Description This PR fixes the non-functional resend confirmation feature on the V3 login page where clicking "Resend confirmation" did nothing. The issue was caused by the V3 store not having the `

### F-013 | 53b2a517d | 2026-05-07
**Author:** Aakash Bakhle
**Subject:** fix: resolve SendReplyJob flaky specs (#14394)
**Files changed:** spec/jobs/send_reply_job_spec.rb
**Body excerpt (if exists):** `CHANNEL_SERVICES`. In test, a request spec can trigger Rails constant reloading after `SendReplyJob` has already been loaded, leaving the job with stale class objects while later specs stub the reloa

### F-014 | e6b8f48b3 | 2026-05-08
**Author:** Tanmay Deep Sharma
**Subject:** fix: settle captain credits on subscription cancellation (#14089)
**Files changed:** enterprise/app/services/enterprise/billing/create_stripe_customer_service.rb, enterprise/app/services/enterprise/billing/handle_stripe_event_service.rb, spec/enterprise/services/enterprise/billing/create_stripe_customer_service_spec.rb
**Body excerpt (if exists):** - https://linear.app/chatwoot/issue/CW-6875/captain-credits-3-bugs-in-stripe-subscription-lifecycle-cancel-ratchet ## Description Fixes Captain credit settlement on subscription cancellation. Previous

### F-015 | cc612e755 | 2026-05-08
**Author:** Shivam Mishra
**Subject:** fix: SafeFetch dependency loading (#14408)
**Files changed:** lib/safe_fetch.rb
**Body excerpt (if exists):** uninitialized constant SafeFetch::Fetcher` across every example that exercised `SafeFetch.fetch`. From a product perspective, this made the external-file fetch path look unreliable even though the fai

### F-016 | 610ee4900 | 2026-05-09
**Author:** genius
**Subject:** fix all chatwoot text to patra in frontend
**Files changed:** app/javascript/dashboard/assets/images/bubble-logo.svg, app/javascript/dashboard/components-next/HelpCenter/PortalSwitcher/CreatePortalDialog.vue, app/javascript/dashboard/components-next/icon/Logo.vue [+8 more]
**Body excerpt (if exists):** none

### F-017 | 905b33d93 | 2026-05-09
**Author:** genius
**Subject:** replace chatwoot blue with patra purple, fix welcome text and logo
**Files changed:** app/assets/stylesheets/administrate/library/_variables.scss, app/assets/stylesheets/administrate/utilities/_variables.scss, histoire.config.ts [+2 more]
**Body excerpt (if exists):** none

### F-018 | 2861607ea | 2026-05-09
**Author:** genius
**Subject:** fix FB_VERIFY_TOKEN comparison in bot controller
**Files changed:** config/initializers/facebook_messenger.rb
**Body excerpt (if exists):** none

### F-019 | dce4bf494 | 2026-05-10
**Author:** genius
**Subject:** Fix AI message type integer check
**Files changed:** app/services/ai/reply_service.rb
**Body excerpt (if exists):** none

### F-020 | a6145d174 | 2026-05-10
**Author:** genius
**Subject:** Fix theme CSS variables
**Files changed:** app/javascript/dashboard/assets/stylesheets/patra-themes.css
**Body excerpt (if exists):** none

### F-021 | d50b00dda | 2026-05-10
**Author:** genius
**Subject:** Fix theme CSS variables
**Files changed:** app/javascript/dashboard/assets/stylesheets/patra-themes.css, app/javascript/entrypoints/dashboard.js
**Body excerpt (if exists):** none

### F-022 | 76e4603b2 | 2026-05-11
**Author:** genius
**Subject:** fix: AI reply, backfill FB names, active status system
**Files changed:** app/jobs/ai/reply_job.rb, app/jobs/webhooks/facebook_bridge_job.rb, app/services/ai/reply_service.rb [+3 more]
**Body excerpt (if exists):** none

### F-023 | 8d024f478 | 2026-05-11
**Author:** genius
**Subject:** fix: bot controller JSON params indifferent access
**Files changed:** app/controllers/webhooks/bot_controller.rb, app/services/facebook/chatwoot_bridge_service.rb
**Body excerpt (if exists):** none

### F-024 | d701d255d | 2026-05-11
**Author:** genius
**Subject:** fix: use Railway internal hostname for SideKiq bridge calls
**Files changed:** .env.example, app/jobs/ai/reply_job.rb, app/jobs/webhooks/facebook_bridge_job.rb [+3 more]
**Body excerpt (if exists):** none

### F-025 | 428a39d2f | 2026-05-11
**Author:** genius
**Subject:** fix: remove all hardcoded localhost:3000, use CHATWOOT_BRIDGE_BASE_URL
**Files changed:** .env.example, app/jobs/ai/reply_job.rb, app/jobs/webhooks/facebook_bridge_job.rb [+3 more]
**Body excerpt (if exists):** none

### F-026 | 0a3dd104d | 2026-05-11
**Author:** genius
**Subject:** fix: graph profile service non-blocking with fallback
**Files changed:** app/services/facebook/graph_profile_service.rb
**Body excerpt (if exists):** none

### F-027 | b56d6343a | 2026-05-11
**Author:** genius
**Subject:** fix: Bella tone - casual human texting, no forced emoji, natural greeting
**Files changed:** app/services/ai/reply_service.rb
**Body excerpt (if exists):** none

### F-028 | 691e89f93 | 2026-05-11
**Author:** genius
**Subject:** fix: Bella stays calm on anger, active status in conversation header
**Files changed:** app/javascript/dashboard/components/widgets/conversation/ConversationHeader.vue, app/services/ai/reply_service.rb
**Body excerpt (if exists):** none

### F-029 | ba4d0ae01 | 2026-05-11
**Author:** genius
**Subject:** fix: owner dashboard auth, player vault sidebar, re-engage button visibility
**Files changed:** app/controllers/api/v1/accounts/owner_stats_controller.rb, app/javascript/dashboard/api/ownerStats.js, app/javascript/dashboard/components/widgets/PlayerProfileCard.vue [+7 more]
**Body excerpt (if exists):** none

### F-030 | c675e495a | 2026-05-11
**Author:** genius
**Subject:** fix: handle nil reporting_timezone in OwnerStats aggregator
**Files changed:** app/services/owner_stats/aggregator.rb
**Body excerpt (if exists):** none

### F-031 | c9a0ff3ff | 2026-05-11
**Author:** genius
**Subject:** fix: detect FB bridge image attachments for AI image flow
**Files changed:** app/jobs/ai/reply_job.rb, app/jobs/webhooks/facebook_bridge_job.rb, app/services/ai/reply_service.rb
**Body excerpt (if exists):** none

### F-032 | 350b55156 | 2026-05-11
**Author:** genius
**Subject:** fix: process image-only FB messages in bridge job
**Files changed:** app/jobs/webhooks/facebook_bridge_job.rb
**Body excerpt (if exists):** none

### F-033 | 93987e240 | 2026-05-11
**Author:** genius
**Subject:** fix: allow image-only FB messages through bot controller
**Files changed:** app/controllers/webhooks/bot_controller.rb
**Body excerpt (if exists):** none

### F-034 | 523366300 | 2026-05-11
**Author:** genius
**Subject:** fix: download FB image bytes and send to Anthropic as base64
**Files changed:** app/services/ai/image_payment_extractor.rb
**Body excerpt (if exists):** none

### F-035 | 07f1bdb90 | 2026-05-11
**Author:** genius
**Subject:** fix: restore emoji_guard if/else in reply_service.rb
**Files changed:** app/services/ai/reply_service.rb
**Body excerpt (if exists):** none

### F-036 | d72ce9359 | 2026-05-12
**Author:** genius
**Subject:** fix: escape special chars in paymentHandles i18n to fix vue parser
**Files changed:** app/javascript/dashboard/i18n/locale/en/paymentHandles.json
**Body excerpt (if exists):** none

### F-037 | bbeb9407a | 2026-05-12
**Author:** genius
**Subject:** fix: smarter pick_backup and pick_active with failure-aware healthy handle selection
**Files changed:** app/services/payments/handle_selector.rb
**Body excerpt (if exists):** none

### F-038 | 767f789b2 | 2026-05-12
**Author:** genius
**Subject:** fix: normalize cancel variants as failed, strengthen fingerprint, expand text failover regex
**Files changed:** app/services/ai/reply_service.rb
**Body excerpt (if exists):** none

### F-039 | 75d59e80e | 2026-05-13
**Author:** genius
**Subject:** fix: stringify form keys to fix Net::HTTP gsub error on Symbol
**Files changed:** app/services/games/game_vault/client.rb
**Body excerpt (if exists):** none

### F-040 | 80930e6d0 | 2026-05-13
**Author:** genius
**Subject:** fix: payment-first gating + auto-create username + honest failures + Telegram debug
**Files changed:** app/controllers/api/v1/accounts/agent_games_controller.rb, app/javascript/dashboard/api/games.js, app/javascript/dashboard/components/widgets/GamePlayerActionsModal.vue [+7 more]
**Body excerpt (if exists):** - Auto-create Game Vault accounts via addUser API when code 8 - DM generated password to customer - Honest failure messages (no more 'fixing now' lies) - Telegram alerts now fire on every load/failure

### F-041 | b44d5a2f4 | 2026-05-13
**Author:** genius
**Subject:** fix: reject flagged duplicate payments + auto-create username intent + 30min window
**Files changed:** app/services/games/conversation_orchestrator.rb, app/services/games/intent_detector.rb
**Body excerpt (if exists):** - find_unloaded_confirmed_payment same tightening - Payment match window tightened: 6 hours to 30 minutes - Case-insensitive status matching - Added image_received_at + transaction_id as backup fields

### F-042 | bfd3212a4 | 2026-05-13
**Author:** genius
**Subject:** Fix: multi-message intent detection + diagnostic logging
**Files changed:** app/services/games/conversation_orchestrator.rb, app/services/games/intent_detector.rb, check.txt [+1 more]
**Body excerpt (if exists):** none

### F-043 | b7e8478a8 | 2026-05-13
**Author:** genius
**Subject:** Fix: cashout migration + cashout method extraction + orchestrator fallback + remove load alerts
**Files changed:** app/services/games/conversation_orchestrator.rb, app/services/games/intent_detector.rb, cashout_dump.txt [+5 more]
**Body excerpt (if exists):** none

### F-044 | 3fa621ff3 | 2026-05-13
**Author:** genius
**Subject:** Fix: remove order(:position) crash in active_payment_handle_for_account
**Files changed:** app/services/games/conversation_orchestrator.rb
**Body excerpt (if exists):** none

### F-045 | e81f722be | 2026-05-13
**Author:** genius
**Subject:** Fix: create game account first, then ask for payment
**Files changed:** app/services/games/conversation_orchestrator.rb
**Body excerpt (if exists):** none

### F-046 | 62a4e8144 | 2026-05-13
**Author:** genius
**Subject:** Fix: Redis lock prevents duplicate AI replies per conversation
**Files changed:** app/jobs/ai/reply_job.rb
**Body excerpt (if exists):** none

### F-047 | 0c88d23cd | 2026-05-13
**Author:** genius
**Subject:** Fix: remove 'account' from username pattern, expand common_word denylist
**Files changed:** app/services/games/intent_detector.rb
**Body excerpt (if exists):** none

### F-048 | eb231a80a | 2026-05-13
**Author:** genius
**Subject:** Fix: match 'need an account' and 'create it' in CREATE_ACCOUNT_PATTERNS
**Files changed:** app/services/games/intent_detector.rb
**Body excerpt (if exists):** none

### F-049 | 2a9b387d3 | 2026-05-13
**Author:** genius
**Subject:** Fix: latest message's game name wins over combined history
**Files changed:** app/services/games/conversation_orchestrator.rb, app/services/games/intent_detector.rb
**Body excerpt (if exists):** none

### F-050 | d9c9d4061 | 2026-05-13
**Author:** genius
**Subject:** Fix: prevent duplicate accounts + add game suffix to username format
**Files changed:** app/services/games/conversation_orchestrator.rb
**Body excerpt (if exists):** none

### F-051 | 28b09b7fb | 2026-05-13
**Author:** genius
**Subject:** Fix: underscore username + replace credentials on different account request
**Files changed:** app/services/games/conversation_orchestrator.rb
**Body excerpt (if exists):** none

### F-052 | 99a3ffd58 | 2026-05-13
**Author:** genius
**Subject:** Fix: password matches username base without game suffix
**Files changed:** app/services/games/conversation_orchestrator.rb
**Body excerpt (if exists):** none

### F-053 | c2300eb0c | 2026-05-13
**Author:** genius
**Subject:** Fix: only trigger account creation if it's in the latest message
**Files changed:** app/services/games/conversation_orchestrator.rb
**Body excerpt (if exists):** none

### F-054 | f3b63ff6f | 2026-05-13
**Author:** genius
**Subject:** Fix: dynamic game name in errors + dont lie when add_player fails
**Files changed:** app/controllers/api/v1/accounts/agent_games_controller.rb, app/services/games/conversation_orchestrator.rb
**Body excerpt (if exists):** none

### F-055 | f2f4c8d58 | 2026-05-13
**Author:** genius
**Subject:** Fix Redis::Alfred.ttl crash in reply_job ΓÇö remove TTL from log line
**Files changed:** app/jobs/ai/reply_job.rb
**Body excerpt (if exists):** none

### F-056 | 8c0a55ba5 | 2026-05-16
**Author:** genius
**Subject:** Add zero-bug rules to .cursorrules
**Files changed:** .cursorrules
**Body excerpt (if exists):** none

### F-057 | 91389261a | 2026-05-17
**Author:** genius
**Subject:** Fix create_player: search-verify + popup ACCOUNT_EXISTS wins
**Files changed:** patra-automation/milky_way/milky_way.py
**Body excerpt (if exists):** none

### F-058 | 913d081aa | 2026-05-18
**Author:** genius
**Subject:** fix(milky_way): sanitize account name + defensive dashboard detection (Bug 12 root cause)
**Files changed:** patra-automation/milky_way/milky_way.py
**Body excerpt (if exists):** none

### F-059 | 8891b5c3d | 2026-05-18
**Author:** genius
**Subject:** fix(fire_kirin/panda_master/orion_stars): port Bug 12 sanitizer fix from milky_way
**Files changed:** patra-automation/fire_kirin/fire_kirin.py, patra-automation/orion_stars/orion_stars.py, patra-automation/panda_master/panda_master.py
**Body excerpt (if exists):** none

### F-060 | 73f9e14d1 | 2026-05-18
**Author:** genius
**Subject:** fix(orchestrator): use contact preferred_platform before falling back to game_vault (Bug 1)
**Files changed:** app/services/games/conversation_orchestrator.rb
**Body excerpt (if exists):** none

### F-061 | bf4c0bd70 | 2026-05-19
**Author:** genius
**Subject:** index on main: 73f9e14d1 fix(orchestrator): use contact preferred_platform before falling back to game_vault (Bug 1)
**Files changed:** (no files listed)
**Body excerpt (if exists):** none

### F-062 | ba49b06e4 | 2026-05-19
**Author:** genius
**Subject:** intent_detector: add 8 missing game slugs to GAME_KEYWORDS + fix GAME_NAME_ALIASES RHS to match ClientRegistry
**Files changed:** app/services/games/intent_detector.rb
**Body excerpt (if exists):** none

### F-063 | 9b40d3e5a | 2026-05-19
**Author:** genius
**Subject:** fix(orchestrator,ocr): bug 1 preferred_platform fallback, bug 7 handle format, bug 5 vision prompt disambiguation
**Files changed:** app/services/ai/image_payment_extractor.rb, app/services/games/conversation_orchestrator.rb
**Body excerpt (if exists):** none

### F-064 | 6b83d193c | 2026-05-19
**Author:** genius
**Subject:** fix(intent_detector): bug 2/3/4 ΓÇö question + negation guards, send-me-X-tag pattern
**Files changed:** app/services/games/intent_detector.rb
**Body excerpt (if exists):** none

### F-065 | ac47d087d | 2026-05-21
**Author:** genius
**Subject:** fix(bella-rag): clean up load_re regex, remove duplicate Phase 5d branches, fix merged-branch bug
**Files changed:** lib/tasks/bella.rake
**Body excerpt (if exists):** none

### F-066 | 39f30ad62 | 2026-05-21
**Author:** genius
**Subject:** Fix Phase 6.1 migration: disable_ddl_transaction + batched backfill, idempotent guards
**Files changed:** db/migrate/20260521140000_bella_rag_pairs_add_scoping_columns.rb
**Body excerpt (if exists):** none

### F-067 | 1f65bf37e | 2026-05-21
**Author:** genius
**Subject:** fix(patra): FB OAuth idempotency, alert() crash fix, already-connected UI, Messenger icon
**Files changed:** app/controllers/api/v1/accounts/patra/facebook_connect_controller.rb, app/javascript/dashboard/components-next/icon/provider.js, app/javascript/dashboard/routes/dashboard/patra/PatraConnectFacebook.vue
**Body excerpt (if exists):** none

### F-068 | 3d346b461 | 2026-05-22
**Author:** genius
**Subject:** fix(patra): byoc oauth url v prefix - facebook_dialog_version was stripping the v
**Files changed:** app/controllers/api/v1/accounts/patra/facebook_connect_controller.rb
**Body excerpt (if exists):** none

### F-069 | deb3eaf40 | 2026-05-23
**Author:** genius
**Subject:** Hotfix: align Zernio parse_inbound + job with real production payload schema
**Files changed:** app/jobs/process_zernio_inbound_job.rb, app/services/messaging/zernio_provider.rb
**Body excerpt (if exists):** none

### F-070 | 9aa5c0e2b | 2026-05-23
**Author:** genius
**Subject:** Phase G Item 0 + Bonus: agent reply gate fix + ZernioController log cleanup
**Files changed:** app/controllers/webhooks/zernio_controller.rb
**Body excerpt (if exists):** none

### F-071 | 3b8000b8f | 2026-05-23
**Author:** genius
**Subject:** fix: Add Channel page + hide My Inbox + multi-platform picker
**Files changed:** app/javascript/dashboard/components-next/sidebar/Sidebar.vue, app/javascript/dashboard/routes/dashboard/dashboard.routes.js, app/javascript/dashboard/routes/dashboard/patra/PatraAddChannel.vue [+1 more]
**Body excerpt (if exists):** none

### F-072 | e84b4c622 | 2026-05-23
**Author:** genius
**Subject:** fix: Add Channel label + contact enrichment + platform expansion + slug mapping
**Files changed:** app/javascript/dashboard/components-next/sidebar/Sidebar.vue, app/services/messaging/inbound_dispatcher.rb, app/services/messaging/zernio_contact_enrichment.rb [+3 more]
**Body excerpt (if exists):** none

### F-073 | eb749fc42 | 2026-05-23
**Author:** genius
**Subject:** fix: duplicate useAlert import breaking vite build
**Files changed:** app/javascript/dashboard/components/widgets/ContactProfileStats.vue, app/javascript/dashboard/components/widgets/conversation/CannedResponseSuggestions.vue, app/javascript/dashboard/components/widgets/conversation/ConversationHeader.vue
**Body excerpt (if exists):** none

### F-074 | 99e6b18a5 | 2026-05-23
**Author:** genius
**Subject:** fix: pin, summary, settings save, canned suggestions, games count, notifications
**Files changed:** app/controllers/api/v1/accounts/patra/conversations_controller.rb, app/javascript/dashboard/api/patraSettings.js, app/javascript/dashboard/components/widgets/conversation/CannedResponseSuggestions.vue [+6 more]
**Body excerpt (if exists):** none

### F-075 | e99720aa2 | 2026-05-23
**Author:** genius
**Subject:** fix: remove summary btn, Copilot to Bella, route suggest+summarize through Grok
**Files changed:** app/javascript/dashboard/components/widgets/conversation/ConversationHeader.vue, app/javascript/dashboard/i18n/locale/en/conversation.json, app/javascript/dashboard/i18n/locale/en/integrations.json [+2 more]
**Body excerpt (if exists):** none

### F-076 | 7663b9a32 | 2026-05-23
**Author:** genius
**Subject:** fix: Captain Grok bypass, re-engage save, canned suggestions, pin state, notifications
**Files changed:** app/controllers/api/v1/accounts/patra/settings_controller.rb, app/javascript/dashboard/components/widgets/conversation/CannedResponseSuggestions.vue, app/javascript/dashboard/components/widgets/conversation/ConversationHeader.vue [+4 more]
**Body excerpt (if exists):** none

### F-077 | b9e835de4 | 2026-05-23
**Author:** genius
**Subject:** fix: remove canned pills, XAI Captain bypass, PSID links, hide integrations, Telegram alert
**Files changed:** app/controllers/dashboard_controller.rb, app/javascript/dashboard/components-next/sidebar/Sidebar.vue, app/javascript/dashboard/components/widgets/PlayerProfileCard.vue [+11 more]
**Body excerpt (if exists):** none

### F-078 | e0779436d | 2026-05-23
**Author:** genius
**Subject:** fix: Bella tone, game routing, reports, username blacklist, payment handles
**Files changed:** app/controllers/api/v1/accounts/patra/reports_controller.rb, app/javascript/dashboard/api/patraReports.js, app/javascript/dashboard/components-next/sidebar/Sidebar.vue [+7 more]
**Body excerpt (if exists):** none

### F-079 | 22696e6c5 | 2026-05-24
**Author:** genius
**Subject:** fix: exact 14 games list, Bella creates accounts, RAG logging
**Files changed:** app/services/ai/reply_service.rb
**Body excerpt (if exists):** none

### F-080 | fb60e0f63 | 2026-05-24
**Author:** genius
**Subject:** fix: expand account creation intents, RAG priority in system prompt
**Files changed:** app/services/ai/reply_service.rb, app/services/games/intent_detector.rb
**Body excerpt (if exists):** none

### F-081 | 5c2d279ee | 2026-05-24
**Author:** genius
**Subject:** fix: post-create verify, juwa2 detection, quick actions panel
**Files changed:** app/controllers/api/v1/accounts/agent_games_controller.rb, app/javascript/dashboard/api/games.js, app/javascript/dashboard/components/widgets/GameQuickActionsPanel.vue [+6 more]
**Body excerpt (if exists):** none

### F-082 | a52cd0ac3 | 2026-05-24
**Author:** genius
**Subject:** fix: FastApi requestid alphanumeric, ASP.NET UTF-8 encoding, verify rescue
**Files changed:** app/services/games/action_executor.rb, app/services/games/asp_net_panel/base_client.rb, app/services/games/fast_api/client.rb
**Body excerpt (if exists):** none

### F-083 | d9e2fa8aa | 2026-05-24
**Author:** genius
**Subject:** fix: sanitize binary encoding before DB write for Cluster 1 games
**Files changed:** app/services/games/action_executor.rb
**Body excerpt (if exists):** none

### F-084 | 5d43eaf01 | 2026-05-24
**Author:** genius
**Subject:** fix: sanitize entire result hash at yield in execute_in_audit
**Files changed:** app/services/games/action_executor.rb
**Body excerpt (if exists):** none

### F-085 | 199b6c086 | 2026-05-24
**Author:** genius
**Subject:** fix: use get_user_id for post-create verify instead of check_balance
**Files changed:** app/services/games/action_executor.rb
**Body excerpt (if exists):** none

### F-086 | 5bed2bb54 | 2026-05-24
**Author:** genius
**Subject:** fix: inactive game returns available games list, no fallthrough to Bella
**Files changed:** app/services/games/conversation_orchestrator.rb
**Body excerpt (if exists):** none

### F-087 | 03f33f1a6 | 2026-05-24
**Author:** genius
**Subject:** fix: fuzzy game name matching, inactive game reply with active list
**Files changed:** app/services/games/intent_detector.rb
**Body excerpt (if exists):** none

### F-088 | a2760caf8 | 2026-05-24
**Author:** genius
**Subject:** fix: safety hardening - verify stored creds, silent fail protection, timeout wrapper
**Files changed:** app/services/games/conversation_orchestrator.rb
**Body excerpt (if exists):** none

### F-089 | 168729f24 | 2026-05-24
**Author:** genius
**Subject:** fix: wrap audit hooks model refs in Reloader.to_prepare
**Files changed:** config/initializers/patra_audit_hooks.rb
**Body excerpt (if exists):** none

### F-090 | 146fdb549 | 2026-05-24
**Author:** genius
**Subject:** fix: add missing script closing tag in ConversationItem.vue
**Files changed:** app/javascript/dashboard/components/ConversationItem.vue
**Body excerpt (if exists):** none

### F-091 | fb58a1a43 | 2026-05-24
**Author:** genius
**Subject:** fix: ConversationCard computed props + verify ConversationItem script tag
**Files changed:** app/javascript/dashboard/components/widgets/conversation/ConversationCard.vue
**Body excerpt (if exists):** none

### F-092 | 56ad1d5ee | 2026-05-24
**Author:** genius
**Subject:** fix: add Resolved sidebar link, remove hover resolve button
**Files changed:** app/finders/conversation_finder.rb, app/javascript/dashboard/components-next/copilot/CopilotLauncher.vue, app/javascript/dashboard/components-next/sidebar/MobileSidebarLauncher.vue [+14 more]
**Body excerpt (if exists):** none

### F-093 | ed39a4aa1 | 2026-05-24
**Author:** genius
**Subject:** fix: merge PLAYER_PROFILE i18n keys into conversation.json to prevent collision
**Files changed:** app/javascript/dashboard/i18n/locale/en/conversation.json, app/javascript/dashboard/i18n/locale/en/patraFeatures.json
**Body excerpt (if exists):** none

### F-094 | da9847282 | 2026-05-24
**Author:** genius
**Subject:** fix: pass PatraRateLimiter as string in initializer to fix autoload boot crash
**Files changed:** config/initializers/patra_rate_limiter.rb
**Body excerpt (if exists):** none

### F-095 | 9ecc0fc7b | 2026-05-24
**Author:** genius
**Subject:** fix: require_relative middleware class in initializer (autoload fix)
**Files changed:** config/initializers/patra_rate_limiter.rb
**Body excerpt (if exists):** none

### F-096 | 8b5ab2966 | 2026-05-24
**Author:** genius
**Subject:** fix: remove duplicate contact_id index in automation_flow_runs migration
**Files changed:** db/migrate/20260524200100_create_automation_flow_runs.rb
**Body excerpt (if exists):** none

### F-097 | 08788b923 | 2026-05-24
**Author:** genius
**Subject:** fix: remove stray end in payments/smart_router.rb (syntax)
**Files changed:** app/services/payments/smart_router.rb, chatwoot-crash.txt, sidekiq-crash.txt
**Body excerpt (if exists):** none

### F-098 | ad9226686 | 2026-05-24
**Author:** genius
**Subject:** fix: rate limiter only throttles anonymous widget/public endpoints, raise cap to 300/min
**Files changed:** app/middleware/patra_rate_limiter.rb
**Body excerpt (if exists):** none

### F-099 | d8d7dbd2b | 2026-05-24
**Author:** genius
**Subject:** fix: add player_bonus inflection rule so Account#player_bonuses resolves
**Files changed:** config/initializers/inflections.rb
**Body excerpt (if exists):** none

### F-100 | d2d7a3843 | 2026-05-24
**Author:** genius
**Subject:** fix(ui): remove dollar/at-symbol from i18n placeholder (vue-i18n was crashing payment handles page)
**Files changed:** app/javascript/dashboard/i18n/locale/en/paymentHandles.json
**Body excerpt (if exists):** none

### F-101 | 9e751fc03 | 2026-05-26
**Author:** genius
**Subject:** fix: force redeploy ledger component
**Files changed:** app/javascript/dashboard/routes/dashboard/settings/integrations/PaymentHandles.vue
**Body excerpt (if exists):** none

### F-102 | 386f2c3c1 | 2026-05-26
**Author:** genius
**Subject:** fix: pending payment honest reply + loading guard + captain 422 xai bypass
**Files changed:** app/services/ai/reply_service.rb, enterprise/lib/enterprise/captain/reply_suggestion_service.rb
**Body excerpt (if exists):** none

### F-103 | 17e2a0d8c | 2026-05-26
**Author:** genius
**Subject:** fix: release reply lock immediately after successful send
**Files changed:** app/jobs/ai/reply_job.rb
**Body excerpt (if exists):** none

### F-104 | 3bd6b3e21 | 2026-05-26
**Author:** genius
**Subject:** fix: nil guard in imap_verifier prevent crash when handle is nil
**Files changed:** app/services/payments/imap_verifier.rb
**Body excerpt (if exists):** none

### F-105 | c0d1699c7 | 2026-05-26
**Author:** genius
**Subject:** fix: use updated_at for freshness check so late Zernio retries dont get skipped
**Files changed:** app/services/ai/reply_service.rb
**Body excerpt (if exists):** none

### F-106 | c5e758499 | 2026-05-27
**Author:** genius
**Subject:** fix: always pass freshness check - job only runs on live webhooks
**Files changed:** app/services/ai/reply_service.rb
**Body excerpt (if exists):** none

### F-107 | 672de8025 | 2026-05-27
**Author:** genius
**Subject:** fix: ambiguous created_at SQL columns in reply_service - prefix with table names
**Files changed:** app/services/ai/reply_service.rb
**Body excerpt (if exists):** none

### F-108 | cdf769574 | 2026-05-27
**Author:** genius
**Subject:** fix: bypass wrong_platform and recipient_mismatch when HandleResolver confident match found
**Files changed:** app/services/ai/reply_service.rb
**Body excerpt (if exists):** none

### F-109 | 922a56cc1 | 2026-05-27
**Author:** genius
**Subject:** fix: extract @handle fields to locals before Mail.defaults block (instance_eval scope)
**Files changed:** app/services/payments/imap_verifier.rb
**Body excerpt (if exists):** none

### F-110 | 401de0390 | 2026-05-27
**Author:** genius
**Subject:** fix: run OCR on image even when duplicate reply lock fires
**Files changed:** app/jobs/ai/reply_job.rb, app/services/ai/reply_service.rb
**Body excerpt (if exists):** none

### F-111 | 99e4750d0 | 2026-05-27
**Author:** genius
**Subject:** fix: retry Gemini OCR once on HTTP 429 rate limit
**Files changed:** app/services/ai/image_payment_extractor.rb
**Body excerpt (if exists):** none

### F-112 | 4edfaeba7 | 2026-05-27
**Author:** genius
**Subject:** add gemini_result debug log
**Files changed:** app/services/ai/image_payment_extractor.rb
**Body excerpt (if exists):** none

### F-113 | cb40a9772 | 2026-05-27
**Author:** genius
**Subject:** fix DB pool exhaustion: release connections in IMAP job + remove all auto-resolve
**Files changed:** app/jobs/payments/imap_check_job.rb, config/schedule.yml
**Body excerpt (if exists):** none

### F-114 | 4b22cd50d | 2026-05-28
**Author:** genius
**Subject:** greeting fix + ask game first + multi-game creation
**Files changed:** app/services/games/conversation_orchestrator.rb, app/services/games/intent_detector.rb
**Body excerpt (if exists):** none

### F-115 | 94cbec3b5 | 2026-05-28
**Author:** genius
**Subject:** fix OCR trigger + cross-platform name match + 2200 char limit
**Files changed:** app/services/ai/reply_service.rb, app/services/messaging/outbound_dispatcher.rb
**Body excerpt (if exists):** none

### F-116 | c0345fc04 | 2026-05-28
**Author:** genius
**Subject:** fix: remove stray comment that crashed sidekiq
**Files changed:** app/services/ai/reply_service.rb
**Body excerpt (if exists):** none

### F-117 | e7e6a87bc | 2026-05-28
**Author:** genius
**Subject:** fix corrupted schedule.yml + per-platform scoring UI
**Files changed:** config/schedule.yml
**Body excerpt (if exists):** none

### F-118 | c80b849f9 | 2026-05-28
**Author:** genius
**Subject:** fix scoring settings save/load - deep permit + expose in API response
**Files changed:** app/controllers/api/v1/accounts_controller.rb, app/javascript/dashboard/components/auth/MfaVerification.vue, app/javascript/dashboard/i18n/locale/en/login.json [+18 more]
**Body excerpt (if exists):** none

### F-119 | cc8dcbbe1 | 2026-05-28
**Author:** genius
**Subject:** fix: signup page blank ΓÇö remove dead loading gate left after testimonials removal
**Files changed:** app/javascript/v3/views/auth/signup/Index.vue
**Body excerpt (if exists):** none

### F-120 | 3e9c077d0 | 2026-05-28
**Author:** genius
**Subject:** fix: accept Email Verified status in payment matching so load works
**Files changed:** app/services/games/conversation_orchestrator.rb
**Body excerpt (if exists):** none

### F-121 | 2a901e66a | 2026-05-29
**Author:** genius
**Subject:** fix false-decline before email check + per-platform breakdown + screenshot date
**Files changed:** app/controllers/api/v1/accounts/payment_handles_controller.rb, app/services/ai/reply_service.rb
**Body excerpt (if exists):** none

### F-122 | 2358f4714 | 2026-05-29
**Author:** genius
**Subject:** perf: optimize landing page for mobile ΓÇö reduce blurs, fix sideways scroll, smoother rendering
**Files changed:** public/patra-landing.html
**Body excerpt (if exists):** none

### F-123 | 1accd1e5e | 2026-05-29
**Author:** genius
**Subject:** Fix Owner Dashboard scroll (overflow-y auto)
**Files changed:** app/javascript/dashboard/routes/dashboard/patra/PatraOwnerDashboard.vue
**Body excerpt (if exists):** none

### F-124 | ded0ba8f5 | 2026-05-29
**Author:** genius
**Subject:** fix send-zero-dollar wording when amount unknown
**Files changed:** app/services/games/conversation_orchestrator.rb
**Body excerpt (if exists):** none

### F-125 | 1f9e74da4 | 2026-05-30
**Author:** genius
**Subject:** fix: move sidebar scss next to ConversationSidebar (fix broken import)
**Files changed:** app/javascript/dashboard/components/widgets/conversation/conversation-sidebar-patra.scss, app/javascript/dashboard/routes/dashboard/conversation/conversation-sidebar-patra.scss
**Body excerpt (if exists):** none

### F-126 | 9d0accf6b | 2026-05-30
**Author:** genius
**Subject:** fix: resolve sidebar scss import via dashboard alias (fix build)
**Files changed:** app/javascript/dashboard/components/widgets/conversation/ConversationSidebar.vue, app/javascript/dashboard/routes/dashboard/conversation/ContactPanel.vue
**Body excerpt (if exists):** none

### F-127 | 9979abaa9 | 2026-05-30
**Author:** genius
**Subject:** guard invalid dates in formatLedgerTime so ledger does not crash on bare times
**Files changed:** app/javascript/dashboard/routes/dashboard/settings/integrations/PaymentHandles.vue
**Body excerpt (if exists):** none

### F-128 | ffb2aa58c | 2026-05-30
**Author:** genius
**Subject:** guard last_failure_at date format so handles page does not crash on load
**Files changed:** app/javascript/dashboard/routes/dashboard/settings/integrations/PaymentHandles.vue
**Body excerpt (if exists):** none

### F-129 | f9b6f6c0e | 2026-05-31
**Author:** genius
**Subject:** Fix PaymentHandles build crash: remove broken escaped Tailwind selectors
**Files changed:** app/javascript/dashboard/routes/dashboard/settings/integrations/PaymentHandles.vue
**Body excerpt (if exists):** none

### F-130 | fd4f24f63 | 2026-05-31
**Author:** genius
**Subject:** Fix last 3 white spots: Companies, Search, Captain layout wrapper bg overrides
**Files changed:** app/javascript/dashboard/components-next/Companies/CompaniesListLayout.vue, app/javascript/dashboard/components-next/captain/PageLayout.vue, app/javascript/dashboard/modules/search/components/SearchView.vue [+3 more]
**Body excerpt (if exists):** none

### F-131 | e3b4ad31d | 2026-05-31
**Author:** genius
**Subject:** Fix: ConversationView shell dark theme (last white spot)
**Files changed:** app/javascript/dashboard/routes/dashboard/conversation/ConversationView.vue
**Body excerpt (if exists):** none

---

## FEATURE COMMITS THAT FIXED BUGS (commits starting with feat: but mentioning a fix in body)

### FX-001 | 202403873 | 2026-05-08
**Author:** Jo├úo Santos
**Subject:** feat: Ability to specify the authentication type for imap server (#12306)
**Files changed:** app/helpers/api/v1/inboxes_helper.rb, app/javascript/dashboard/i18n/locale/en/inboxMgmt.json, app/javascript/dashboard/routes/dashboard/settings/inbox/ImapSettings.vue [+10 more]
**Body excerpt (if exists):** ## Description This PR adds IMAP authentication mechanism selection to Chatwoot's email inbox configuration. Users can now choose between 'plain', 'login', and 'cram-md5' authentication methods when c

### FX-002 | c4aeea19c | 2026-05-29
**Author:** genius
**Subject:** feat: auth light/dark mode via CSS variables + mobile perf fixes
**Files changed:** app/javascript/v3/App.vue, app/javascript/v3/components/Auth/AuthNavBar.vue, app/javascript/v3/components/Auth/AuthThemeToggle.vue [+12 more]
**Body excerpt (if exists):** none

---

## INFRA / DEPLOY / CHORE FIXES
(chore:, refactor:, deploy: commits that mention fixes or rollbacks — same format, "C-" prefix)

### C-001 | 624c6c90f | 2026-05-04
**Author:** Vishnu Narayanan
**Subject:** chore: sync GitHub security advisories to Linear (#14359)
**Files changed:** .github/workflows/ghsa-linear-sync.yml
**Body excerpt (if exists):** Fixes https://linear.app/chatwoot/issue/CW-7006

### C-002 | aa10d4223 | 2026-05-08
**Author:** Aakash Bakhle
**Subject:** chore: bump RubyLLM version [AI-152] (#14387)
**Files changed:** Gemfile, Gemfile.lock, config/llm_models.json
**Body excerpt (if exists):** ## Description Bump RubyLLM version and update model registry ## Type of change Version bump on package ## How Has This Been Tested? Please describe the tests that you ran to verify your changes. Prov
