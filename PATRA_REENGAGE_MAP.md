# PATRA RE-ENGAGEMENT SENDER MAP (H11 — 2026-06-10, verified by read)

Four daily cron jobs touch dormant players. They are staggered and ALL real senders share
one anti-spam stamp: `contact.custom_attributes['last_automated_contact_at']`
(`Reengagement::ContactCooldown`, window `PATRA_REENGAGE_COOLDOWN_HOURS`, default **72h**).
A contact touched by ANY automated sender is off-limits to EVERY automated sender for the
window. Each job keeps its own longer job-specific cooldown on top.

| UTC | Cron name | Class | Sends? | Audience / channel | Own cooldown | Shared cooldown |
|---|---|---|---|---|---|---|
| 08:00 | contacts_re_engage_job | Contacts::ReEngageJob | YES — MessageBuilder into last open conversation | any-channel contacts inactive > reengage_days (default 7) with a game username; blacklist + opted_out respected | 30d via AuditLog re_engage_sent | checks `on_cooldown?` before send (re_engage_job.rb:38) + `stamp!` after (:45) |
| 09:00 | reengage_dormant_contacts_job | ReengageDormantContactsJob | NO — log-only ("would message") | resolved conversations dormant > reengage_days | n/a | n/a (sends nothing) |
| 12:00 | reengagement_dormant_player_job | Reengagement::DormantPlayerJob → Reengagement::SendService | YES — MessagePicker message into dormant FB Messenger conversation | FB Messenger contacts, loyalty_tier present and != new, ≥7d quiet | 14d via last_reengagement_date | checks `ContactCooldown.on_cooldown?` (send_service.rb:18) + stamps KEY (:73) |
| 17:00 | games_winback_job | Games::WinbackJob → Games::WinbackService (OWNER-WIP, read-only) | YES (mode-dependent: auto-send or manual Telegram suggestion) | dormant players per ReplyPreference winback settings | winback_days via winback_last_contacted_at | checks `ContactCooldown.on_cooldown?` (winback_service.rb:70) + stamps KEY in stamp_contacted! (:311) |

## Guarantees
- No player is messaged twice across senders within the shared window (72h default):
  every sender checks before sending and stamps after sending.
- Stagger: sends are spread 08:00 / 12:00 / 17:00 (09:00 job is log-only) — no same-minute
  collisions, and the shared stamp makes ordering irrelevant anyway.
- Tuning: set `PATRA_REENGAGE_COOLDOWN_HOURS` (env). Zero/garbage falls back to 72 —
  the guard never silently disables itself.

## Notes
- Winback is owner-WIP: its cooldown integration was ALREADY present and is verified by
  read only — no edits were made to winback_service.rb in this run.
- Proof: tmp/self_tests/h11_shared_cooldown_test.rb (cross-sender, both directions) +
  spec/services/reengagement/contact_cooldown_spec.rb.
