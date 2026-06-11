# PATRA MASTER LOG

Running master log of engineering sessions. One entry per day per major run.
Detailed per-run logs live in their own files (PATRA_*_LOG.md).

---

## 2026-06-11 — MEGA RUN 2 (money hardening + Telegram ops + hot-file pass + ops guards)

Full detail: PATRA_MEGA2_LOG.md. ROLLBACK=665b6985de6b9f71e15ab0918f805af137e1bc97.

- **pg-trigger outage + lesson** (other chat today, Genius-reported): the
  conversations/campaigns display_id hairtriggers + per-account sequences are
  single points of failure — when a trigger/sequence is missing, inserts crash
  account-wide. Lesson: never assume schema objects survived a restore/migration;
  verify them. This run shipped `script/patra_db_integrity_check.rb` (report-only
  probe: triggers, unique indexes, NOT NULLs, sequence last_value >= max(id), FKs)
  to catch that class of outage before it bites.
- **Referral-hijack rule** (MEGA2 P1, verified in code): NEVER link a pending
  Referral to an account-creator unless the match is deterministic
  (`referred_contact_id` already points at that contact, exactly one match).
  Ambiguous pendings stay pending + one 5-part escalation per contact. The old
  "newest pending wins" behavior let any stranger absorb someone else's
  referral credit.
- **Brand/notification fixes** (other chat today, Genius-reported): brand and
  notification-channel fixes landed in a parallel session — see that chat's log.
- **Harness 174/174** (Genius-reported): script/patra_money_harness.rb passing
  174/174 before this run; harness assertions untouched by MEGA2.
- **New settings introduced by MEGA2** (all default to today's behavior):
  - `PATRA_TELEGRAM_COMMANDS` (ENV, default unset=OFF) — inbound approve/deny
    Telegram commands.
  - `PATRA_TELEGRAM_OPS_WEBHOOK_SECRET` (ENV, default unset = secret check dark).
  - account `custom_attributes['cashout_overmax_mode']` — `cash_whole` (default)
    | `pay_max_recharge` | `ask_first`.
  - account `custom_attributes['freeplay_min_deposits']` — default 1, 0 disables
    the freeplay-farm guard.
  - `PATRA_STUCK_MINUTES` (ENV, default 30) — stuck-pending sweeper age.
  - account `custom_attributes['handle_decay_days']` — default 7, 0 disables
    payment-handle failure_count decay.
