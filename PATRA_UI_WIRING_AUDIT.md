# PATRA UI <-> BACKEND WIRING AUDIT — TAB A (2026-06-10 overnight)

Method: every Patra settings control inventoried from app/javascript (load + save calls), then each
saved field traced to its REAL backend consumer (read-verified file:line). Verdicts:
**WIRED** = loads live value, persists, and the saved value changes runtime behavior.
**WIRED-TONIGHT** = was decorative, wired by TAB A tonight (commit noted).
**DECORATIVE** = persists but no backend consumer (saving changes nothing).
**BACKEND-MISSING** = persists; consumer exists but reads a DIFFERENT source.

## 1. Automation & Safety (settings/automation-safety → /reply_preference)
| Control | Verdict | Consumer (read-verified) |
|---|---|---|
| transfer_mode | WIRED | orchestrator transfer_mode_pref :2645 |
| transfer_deposit_shortfall_mode | WIRED | orchestrator :2653 |
| winback_enabled | WIRED | winback_service.rb:32 (scope on the flag) |
| winback_dormant_days_vip/regular/new | WIRED | winback_service.rb:291-295 |
| fraud_cashout_velocity_count/hours | WIRED | orchestrator cashout_velocity_state :2691-2698 |
| fraud_duplicate_payment_check | WIRED | orchestrator duplicate_payment_check_enabled? :2713 |
| payment_reply_source | WIRED | orchestrator payment_reply_source_pref :2951 |

## 2. Reply Style / Bella persona (settings/reply-style → /reply_preference)
| Control | Verdict | Consumer |
|---|---|---|
| reply_tone, max_reply_lines, use_emojis, sign_off_text | WIRED | reply_service build_rag_enhanced_prompt :2734-2753 |
| use_rag_examples, rag_example_count | WIRED | reply_service fetch_rag_examples :2670-2672 |
| memory_enabled | WIRED | reply_service player_memory_lines :1581 + rotate job (write side) |
| confirm_before_load | WIRED | orchestrator handle_load_intent :326 |
| confirm_before_cashout | WIRED | orchestrator handle_cashout_intent :976 |
| auto_send_receipt | WIRED | orchestrator apply_receipt_preference :3189 |

## 3. Referrals (settings/referrals → /referrals/settings, stored on ReplyPreference)
| Control | Verdict | Notes |
|---|---|---|
| referral_enabled | **WIRED-TONIGHT** (commit 7aa71e219) | was persisted but NEVER read; now the auto-pay kill switch (default OFF) |
| referral_bonus_referrer / referral_bonus_new_player | **WIRED-TONIGHT** (7aa71e219) | amounts were hardcoded $5/$5 in ReferralBonusService |
| referral_require_deposit | **WIRED-TONIGHT** (7aa71e219) | was always-on regardless of setting |
| referral_bonus_type | **WIRED-TONIGHT** (7aa71e219) | only 'freeplay' auto-pays; other types stay 'verified' for manual handling |
| referral_tracking_method | DECORATIVE | persisted, no consumer anywhere |
| referral_message_referrer / referral_message_new_player | DECORATIVE | persisted, no consumer (bonus replies are hardcoded in orchestrator/service) |
NOTE: BUG-4 (wrong username key) meant referral auto-pay could never fire at all before tonight;
it is now functional AND gated behind referral_enabled=false by default.

## 4. Player Tiers (settings/player-tiers → /player_tiers)
| Control | Verdict | Consumer |
|---|---|---|
| name/color/badge_text/sort_order | WIRED | display + tier lookup |
| auto_promote_after_deposits / auto_promote_deposit_threshold | WIRED | tier_auto_promote_service.rb:17,35-37 |
| (tier overrides e.g. freeplay_amount) | WIRED | player_tier.rb override_for :13; orchestrator :637; blocked? :18 gates freeplay+cashout |

## 5. Game Rules (settings/game-rules → /game_rules)
All freeplay fields (enabled/amount/max per day/week/require_deposit_first/message),
all deposit-bonus fields (enabled/percentage/min/max_bonus/first_only/message),
all cashout fields (enabled/multipliers/min/max/require_screenshot/rules_text),
links (download/web/auto_send_on_create): **WIRED** — consumed throughout
conversation_orchestrator (freeplay :578-637, bonus :727-766 + GameRule#calculate_bonus
caps at deposit_bonus_max_bonus model :41-46, cashout :880-966, links :2846-2882) and
reply_service dynamic_game_rules_prompt :2643.

## 6. Payment Handles (settings/integrations/payment_handles → /payment_handles)
| Control | Verdict | Consumer |
|---|---|---|
| platform/handle/display_name/priority/status/notes | WIRED | HandleSelector, orchestrator top_handle_for_platform, reply_service payment_handles_context, F9 fallback |
| verification_email(+host/port/ssl) | WIRED | IMAP confirmation (EmailConfirmationService / launch_readiness §3) |
| payment scoring weights + thresholds (account custom_attributes.payment_scoring_config) | WIRED | EmailConfirmationService.confidence_score + scoring_config_for (reply_service :706-708) |

## 7. Games integration (settings/integrations/games → /agent_games)
| Control | Verdict | Notes |
|---|---|---|
| activate/status toggle, config modal, player actions | WIRED | agent_games + ActionExecutor |
| Test connection / Test All | WIRED (read-only health) | POST /agent_games/:id/test_connection |
**IP WHITELIST NOTE (operator-facing):** the game-panel IP whitelist is EXTERNAL — set on each
game's own panel. Patra only DISPLAYS connection health via Test Connection; the UI does NOT and
CANNOT control whitelisting. Morning move: whitelist .244/.245 on each panel, then "Test All" must go green.

## 8. Patra Business Settings (settings/general → /patra/settings, account custom_attributes)
| Control | Verdict | Consumer |
|---|---|---|
| auto_resolve_hours | WIRED | jobs/conversations/auto_resolve_job.rb:9,28 |
| reengage_days | WIRED | jobs/contacts/re_engage_job.rb:9 + reengage_dormant_contacts_job.rb:8 |
| reengage_message | WIRED | re_engage_job.rb:11 |
| cashout_approval_threshold | WIRED | approvals/cashout_approval_gate.rb:8 (default 500) |
| round_robin_enabled / max_conversations | WIRED | assignment/round_robin_service.rb:33 |
| keyword_tag_mapping | WIRED | conversations/auto_tagger.rb:30 |
| business_hours (start/end/tz/days) | WIRED | ai/business_hours_checker.rb:6 + enhanced_business_hours_checker.rb:11 |
| webhook_url | **BACKEND-MISSING** | only the controller's test_webhook ever POSTs to it; no event listener emits real events to this URL (webhook_listener.rb uses inbox.channel.webhook_url — a different field) |
| first_response_limit_minutes | **BACKEND-MISSING** | Sla::CheckViolationsJob reads account.sla_policies.first_response_time_threshold (check_violations_job.rb:28), NOT this field |
| resolution_limit_minutes | **BACKEND-MISSING** | no consumer at all (job only checks first response) |
| sla_alerts_enabled | **BACKEND-MISSING** | checked nowhere — SLA telegrams fire regardless of the toggle |

## HANDOFFS (backend gaps are TAB B lane — exact diffs in PATRA_OVERNIGHT_RUN_LOG.md HANDOFF-B)
- HANDOFF-B-1: wire sla_alerts_enabled + first_response_limit_minutes into Sla::CheckViolationsJob.
- HANDOFF-B-2: decide webhook_url semantics (emit conversation events or remove the field from UI).

## DECORATIVE summary (safe, no action needed tonight)
referral_tracking_method, referral_message_* (persisted only).
