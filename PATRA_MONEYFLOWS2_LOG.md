# PATRA MONEY-FLOWS RUN 2 - LOG

## ROLLBACK
Rollback hash (state before this run): `fa8c418acd1d32e9510c2066d69ef58d03e5de28`
Full rollback: `git reset --hard fa8c418acd1d32e9510c2066d69ef58d03e5de28`

## MORNING SUMMARY
(filled at end of run)

## RULE CHECKLIST
- [ ] S1 status_check: re-verify + window scan + complete-undone-via-guards + real-state replies
- [ ] S2 balance_check: classify ask, live balance, no-invented-numbers, signup offer
- [ ] S3 payment_sent: email match (name+amount+window), sender memory, 2-miss escalate, never load unverified
- [ ] Final log + dump

## PHASE 0 FINDINGS (verified by reading the files this session)

### The 3 handlers today (placeholders)
- handle_status_check (orchestrator:2204): reports the last GameAction's recorded status only.
  Does NOT complete undone work, does NOT scan the window, no-history reply asks "which game?".
  Uses `conversation.contact` (crashes with nil conversation).
- handle_balance_check (orchestrator:2382): always treats the ask as a game-balance question;
  queries live balance via execute_game_api('agent_balance') (already begin/rescue-wrapped, never
  invents a number); no-username reply asks "which username?" instead of offering signup; no
  ambiguity handling; escalations are one-liners.
- handle_payment_sent_confirmation (orchestrator:2173): fires EmailConfirmationService.check_all,
  sets a WRITE-ONLY flag `awaiting_imap_confirmation` (zero readers in app/ - verified by grep),
  telegrams a one-liner, replies "checking now - will load once confirmed!" but NEVER loads,
  never matches, never asks for a screenshot, no sender memory, no miss counter.

### What already EXISTS (reuse, don't rebuild)
- IMAP extraction: Payments::EmailConfirmationService#check_all walks patra_finance_logs entries
  with raw_status pending/completed, verifies via Payments::ImapVerifier (real IMAP), and ON MATCH
  stamps the entry: email_confirmed=true, email_confirmed_at, status='Email Verified',
  email_subject/from/date, email_body_snippet, email_amount (parsed $), email_sender_name (parsed
  from subject/body). THIS is the email record S3 matches against.
- Screenshot/OCR: Ai::ImagePaymentExtractor (Gemini vision), invoked from reply_service (FORBIDDEN
  file) when an image arrives; it writes the finance-log entry with amount, sender_name (OCR),
  recipient_name, transaction_id, image_url, image_received_at. The orchestrator only ever READS
  these entries - no vision calls needed in this run.
- Payments::SenderNameMatcher: name+amount(+note) matching over ghost pool -> contact vault ->
  live IMAP, 30-min window, used by reply_service's conversation-level sender flow. NO persistent
  sender-name memory on the contact anywhere (the flow re-asks every time).
- Payments::SingleContactImapJob: post-IMAP scoring (0-100 confidence) -> announce/escalate.
- patra_finance_logs entry shape (contact.custom_attributes['patra_finance_logs'], Array<Hash>):
  id / transaction_id / image_url / status ('Confirmed'/'Email Verified'/'Loaded'...) / raw_status /
  amount / platform / recorded_at / image_received_at / sender_name (OCR) / recipient_name /
  email_confirmed / email_confirmed_at / email_amount / email_sender_name / email_date /
  flag_reason / game_load_success / loaded_at / loaded_game_slug / load_announced.
- Conversation window: reply_service builds `messages` from the last HISTORY_LIMIT=50 messages
  (role/content hashes) and passes them into the orchestrator - the ~50-message window is ALREADY
  in `messages`; no new fetch needed.
- Normal load path with every guard (F12 deterministic order_id, R7 threshold, blacklist, dup
  guards): handle_load_intent + find_matching/find_unloaded_confirmed_payment (accept 'Email
  Verified' status). Run 1's escalation_context (R8) is available for all new escalations.

### What needs BUILDING
- S1: window scan for unresolved load asks, completion routing through handle_load_intent,
  real-state replies with time-ago, R8 escalations, nil-conversation safety.
- S2: ask classification (cashout-limit -> R3 math via game_rules_for + last_deposit_for_cashout,
  both already exist from Run 1; load-status -> S1), multi-username disambiguation, signup offer
  wired to the EXISTING pending_transfer_create yes/no path (amount 0 = create only, no load).
- S3: claim extraction (text + newest screenshot log entry), verified-email match
  (sender+amount+time window), persistent sender memory (new contact key), miss counter,
  2-miss-then-escalate, already-loaded refusal, auto-load via handle_load_intent.

## DECISIONS
- D1 (S1 completes LOADS only): a verified-but-unloaded payment or an unresolved load ask is
  finishable, verifiable work and re-runs through handle_load_intent where F12 no-ops redone work
  and R7/approval gates apply. Cashout asks are NOT auto-completed from a status check (nothing
  verifiable on our side; re-firing would re-ping the cashier) - their state is reported instead.
- D2 (awaiting_imap_confirmation dropped): the flag has zero readers (grep) - the S3 rewrite
  replaces it with a real match flow and a miss counter; not setting a dead flag is not a
  behavior change.
- D3 (S3 miss counter location): operator said "on the conversation"; conversation can be nil
  (harness + some API paths), so the counter lives on conversation.additional_attributes when a
  conversation exists and falls back to contact.custom_attributes otherwise (same key
  'payment_match_misses'). Reset on any successful match.
- D4 (S3 match source = finance-log email stamps): matching runs over the
  EmailConfirmationService-stamped entries (email_confirmed/email_sender_name/email_amount/
  email_date) instead of re-driving raw IMAP from the orchestrator - the existing service already
  owns IMAP; the orchestrator stays read-only on email. check_all is still triggered first for
  freshness.
- D5 (S2 signup offer reuses pending_transfer_create): the existing yes/no confirmation block +
  complete_pending_transfer_create(slug, amount 0) already creates an account with creds and no
  load - exactly the "routes into the existing account-creation path" the rule asks for. No new
  pending mechanism.
- D6 (sender memory key): contact.custom_attributes['payment_sender_name'] (new key; grep shows
  no collision). Stored on first verified match, auto-checked on later payments; the name question
  is only asked when there is no known name or the known name does not match the email.
- D7 (names_overlap): EmailConfirmationService.names_overlap? is private_class_method - the
  orchestrator gets a small local first-token-containment equivalent instead of reaching into a
  private API.

## ASSUMPTIONS
- A1: Local Rails cannot boot; proof is ruby -c + additive harness cases. Render harness is the gate.
- A2: In the harness, EmailConfirmationService#check_all is instance-stubbed (alias + restore in
  ensure) so S3 scenarios touch zero IMAP even though entries without raw_status would already be
  skipped (needs_email_confirmation?(nil) is false).
- A3: PATRA_PAYMENT_MATCH_WINDOW_MINUTES is an ENV setting (default 10) per the operator's naming;
  not a reply_preferences column.
- A4: The S3 claim's timestamp is the screenshot's image_received_at when one exists, otherwise
  "now" - the match window compares the email timestamp against that.

## SETTINGS/KEYS ADDED THIS RUN
| Key | Where | Default | Meaning |
|-----|-------|---------|---------|
| PATRA_PAYMENT_MATCH_WINDOW_MINUTES | ENV | 10 | max minutes between claimed/screenshot time and email time for an S3 match |
| payment_sender_name | contact.custom_attributes | - | remembered verified sender name (S3b) |
| payment_match_misses | conversation.additional_attributes (contact fallback) | 0 | S3 consecutive no-match counter |

## PER-RULE COMMITS
(filled as commits land)
