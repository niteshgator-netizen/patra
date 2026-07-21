# Plan: Stop RAG copy-paste leaks + replay all 2,057 real chats as an end-to-end test

## Context

Bella (the AI cashier) replied "cash out $66 for Bethany" in a live test — Bethany and
$66 came straight out of an old training chat, not from the actual customer. Root cause
(verified in code this session): retrieved training examples are pasted **word-for-word**
into her prompt with the instruction "reply in the SAME style," and nothing anywhere
scrubs usernames or amounts. Separately, Genius has 2,057 JSON files of real past chats
(`D:\downloads\ho\messages_collected`) and wants everything — account creation, load,
bonus, cashout with play-through, payment step, freeplay — tested end-to-end through the
real backend (no browser) before going live, using those real customer texts as the
script but with fresh TEST usernames, never the historical ones.

Two changes, shipped as two separate commits on branch
`claude/test-cashout-bonus-features-mdfz0m`:

---

## CHANGE 1 — Stop the copy-paste leak (commit 1)

**File: `app/services/ai/reply_service.rb` ONLY** (hot file #1, now 3,619 lines —
hotcheck skill + full read before editing, def/end balance check after, ~130-line diff,
nothing else in this commit).

### 1A. Clean the examples BEFORE they reach the prompt
- New private method `sanitize_rag_example_text(text)` (above `build_rag_enhanced_prompt`,
  ~line 3494): replaces `$66`-style figures with `$X`, "66 bucks" with "X bucks",
  username-shaped tokens (letters+digits, ≥5 chars) with `[username]`, and capitalized
  name-like words not in a stopword list with `[name]`. Fail-open rescue returns raw text.
- Edit `build_rag_enhanced_prompt` (lines 3498-3502): map each example through the
  sanitizer; replace wrapper wording with: examples show *TONE and FLOW only*;
  "NEVER copy names, usernames, or dollar amounts from examples — those belong to OTHER
  customers. Use ONLY this customer's own details."
- SYSTEM_PROMPT: 2 surgical line edits (line ~189 "follow their style and actions
  exactly" → style yes / other customers' names+amounts never; add one bullet after the
  RAG PRIORITY block at ~198 saying example names/usernames/amounts are other customers').
- RAGShortcut path (~line 586): set `@rag_examples` from the shortcut's source pair so
  the new guard also covers `Bella::QuickRephrase` output (it already exits through
  `guard_against_false_load_claim` at line 603).

### 1B. Catch any leak that still gets through (post-generation guard)
- New constant `RAG_LEAK_STOPWORDS` (near `BALANCE_FIGURE`, ~line 2824): flat frozen
  lowercase Set (~60-80 entries) — all 14 game names from SYSTEM_PROMPT line 181,
  payment platforms (cashapp/chime/venmo...), weekdays, common capitalized texting words.
- New private methods (after `customer_provided_numbers`, ~line 2860):
  - `rag_example_leak_candidates` — memoized; mines `@rag_examples` texts for
    name-like tokens (`[A-Z][a-z]{3,}` minus stopwords), username-shaped tokens
    (≥5 chars), and `$` amounts.
  - `rag_leak_allowed_text` — memoized lowercase blob of everything Bella IS allowed
    to say: full current conversation, last incoming message, this contact's
    name + custom_attributes, configured payment handles, account game names.
  - `guard_against_rag_example_leakage(reply_text)` — no-op if `@rag_examples` blank;
    flags a token only if it came from an example AND is ≥4 chars AND not stopworded
    AND absent from allowed text AND word-boundary-matches the homoglyph-folded reply.
    Amounts flagged only if they exactly match an example `$` figure not present in
    the conversation or `customer_provided_numbers`. On leak: log
    `BLOCKED_RAG_EXAMPLE_LEAK`, label `blocked-rag-example-leak`, return defer line
    `'one sec, lemme double-check that for you 🙏'`. Fail-open rescue.
- Chain it inside `guard_against_false_load_claim` immediately after the
  invented-balance link (after line 2518) — covers all 5 reply exits including the
  orchestrator short-circuit and RAGShortcut.

### Change 1 verification
1. Local (Claude Code): `ruby -c app/services/ai/reply_service.rb`.
2. Render Shell probe (Genius pastes one rails-runner line — provided in DUMP): feeds a
   fake example containing "Bethany / $66", asserts the guard rewrites the leaky reply,
   passes the clean one, and shows sanitizer output `$X` / `[name]` / `[username]`.
3. Change 2's `source-chat-leak` grader is the standing regression test.

---

## CHANGE 2 — Replay harness for the 2,057 real chats (commit 2)

**File: NEW `script/patra_convo_replay_harness.rb`** (~900 lines, self-contained like
the other harnesses; zero app-code changes; not a hot file). Runs on **Render only**
(agent_games credentials are encrypted); local gate is `ruby -c`.

### Corpus into the repo (Genius, PowerShell — in the DUMP)
Size-check the folder first (stop if >100 MB), then copy
`D:\downloads\ho\messages_collected` → `test_corpus\messages_collected`, git add/commit.
Script reads `DIR` env (default `test_corpus/messages_collected`).

### Parser (auto-detect, no sample available)
`JSON.parse` each file (failures → "unparseable" report section, never crash); find the
message array (root array, or breadth-first search for array-of-hashes with text-ish +
sender-ish keys; handles Facebook-export shape, sorts by `timestamp_ms` ascending).
Customer-vs-agent sides: explicit role values → `AGENT_NAMES` env override →
corpus-frequency pass (a sender in >20% of files = the page/agent) → name regex.
Unresolved files reported with top sender names so Genius can set `AGENT_NAMES`.
**Noise filter (per Genius: files contain lots of trash):** each file is one distinct
customer; drop everything that is not a real customer text turn — system/event entries
(missed/started call notices, "changed the theme", "reacted to", nickname changes,
polls), attachment-only/sticker-only messages, email-notification bodies, and ALL
cashier/agent-side messages (used only as expectation hints, never fed). Detection:
Facebook-export event shapes (`call_duration`, `is_unsent`, empty `content` +
`photos/audio_files/sticker`) plus regex list for system phrasings. The report counts
filtered items per category per file, so Genius can spot-check that the cleaner isn't
throwing away real customer lines.
Per chat, mine `source_tokens` (names/usernames/$ amounts from BOTH sides) for the leak
grader. Fed customer turns get identity substitution: historical customer name /
"username is X" patterns → `TESTER_<n>` / `tester<n>` (each substitution logged).
Historical agent turns are never fed — Bella's own replies form the assistant side.

### Stub bundle (copied from `script/patra_money_harness.rb:36-104`, made thread-safe)
- `Games::ClientRegistry.client_for` → per-thread FakeClient — **always, every mode; no
  real panel ever**. Abort at boot if stub install fails.
- `Games::TelegramNotifier` (all 11 class methods): `TELEGRAM=fake` (default) recorder;
  `TELEGRAM=live` real sends through a rate limiter (`TG_RATE`=15/min, hard cap
  `TG_MAX`=100 then auto-degrade to recorder); live refuses >25 conversations unless
  `FORCE_LIVE=1`.
- `Approvals::CashoutApprovalGate.create_request!`: `GATE=fake` recorded / `GATE=live`
  real rows (walkthrough mode — Genius presses "paid" in Telegram).
- `Ai::DeepseekClient.complete` canned except MODE=full; email confirmation no-op;
  blacklist false; pin `referral_enabled: false` (snapshot+restore in ensure);
  `AUTOCONFIRM=1` injects a synthetic "yes" turn when Bella asks a confirm question.

### Modes (ENV)
- `MODE=route` (default): all 2,057 chats, `Games::IntentDetector.detect` per customer
  turn, zero LLM, zero writes — minutes.
- `MODE=execute`: full orchestrator execution with FakeClient; orchestrator-nil turns
  recorded as `routed=llm`, no DeepSeek.
- `MODE=full`: execute + real DeepSeek replies on orchestrator-nil turns
  (`LIMIT`=150 default, stratified across flow classes from the route pass; raise LIMIT
  to scale up). Aborts without `DEEPSEEK_API_KEY`.
- Also: `THREADS` (1 default; 6-8 recommended, clamped to AR pool−1,
  `with_connection` per worker), `RESUME=1` (checkpoint `tmp/convo_replay_checkpoint.json`),
  `PARSE_ONLY=1` (format/side-detection stats only), `NO_PREAMBLE`, `AGENT_NAMES`,
  `DIR`, `REPORT_PATH`.

### Per-chat replay (execute/full)
Fresh `Contact` `TESTER_<n>` + ContactInbox (Channel::Api) + `Conversation`, labeled
`harness-test` immediately. If the chat has money intents but no account-creation
intent, feed a synthetic preamble through the REAL pipeline ("can you make me an account
on <game>" → "tester<n>"), assert `add_user` fired and
`custom_attributes['game_username_<slug>']` set (fallback: direct prime, recorded).
Then feed customer turns one at a time: fresh
`Games::ConversationOrchestrator.new(account:, contact:, conversation:, messages:).handle`
per turn, SAME conversation object so state (pending_cashout, confirm flags) persists
like production. Replies pass through the real guard chain via a per-conversation
`Ai::ReplyService` instance (corpus_replay pattern, lines 388-426). MODE=full runs the
proven Tier-2 direct DeepSeek invocation (`build_system_prompt` + `invoke_anthropic`)
for orchestrator-nil turns — deliberately NOT `ReplyService#call` (it fetches over the
Chatwoot HTTP bridge + 10-min freshness gate).

### Graders
- Style set copied from `script/patra_corpus_replay.rb:428-456` (≤2 lines, no bullets,
  no AI admission, configured handles only, no untraceable amounts, no dead-ends).
- Execution asserts (money-harness style): load → exactly one `recharge` with right
  amount + `tester<n>` username; cashout in-limits → `withdraw`; over-limit/play-through
  → approval AND no `withdraw`; freeplay amount + daily limit; creation → `add_user`
  with TEST username. **Any historical username reaching FakeClient = HIGH violation.**
- NEW `source-chat-leak` grader: source-JSON tokens (same filter algorithm as Change 1)
  found in a Bella reply, or source $ amounts not in the fed conversation = HIGH.
  Counts `blocked-rag-example-leak` labels (proves Change 1 guard is live).
- Verdict: PASS = zero HIGH violations; style violations tallied separately.
- Defensive tripwire: report per-label routing counts incl. any RAG_TO_INTENT_MAP
  nil/missing entries. (Verified this session: map now covers ALL 27 labels —
  CLAUDE.md's "16 of 27" is stale. No map changes in this change.)

### Report / cleanup
`PATRA_CONVO_REPLAY_REPORT.md` (pass/fail headline, per-flow + per-intent tables, leak
violations verbatim, unparseable files, Telegram live-sent list) +
`tmp/convo_replay_results.jsonl` detail + atomic checkpoint. `ensure`: destroy tracked
conversations/contacts (+ sweep of stray `TESTER_%` contacts created after run start),
delete their GameActions and walkthrough ApprovalRequests, restore stubs and pins.
Never touches any conversation it didn't create.

### Change 2 verification / run order (Render Shell, Genius runs)
1. `ruby -c script/patra_convo_replay_harness.rb` (local, me).
2. `PARSE_ONLY=1 bundle exec rails runner script/patra_convo_replay_harness.rb`
3. route sweep (all 2,057) → 4. `MODE=execute THREADS=6 RESUME=1 ...`
5. `MODE=full LIMIT=150 THREADS=6 RESUME=1 ...`
6. Walkthrough: `MODE=full LIMIT=3 TELEGRAM=live GATE=live ...` — Genius presses "paid"
   in Telegram group -5243223053.

---

## Decisions surfaced to Genius (in the DUMP, not silently decided)
1. **Telegram**: he asked "always live," but 2,057 live chats would flood the group and
   hit Bot API limits. Design = fake for bulk sweeps, live (rate-limited, ≤25 chats) for
   the walkthrough where he actually pays. He confirms or overrides with FORCE_LIVE=1.
2. **Corpus commit**: real customer names in a private repo + folder size check before
   he commits `test_corpus/`.
3. **MODE=full scale**: 150 replies default (his approved tier), LIMIT raisable.

## Sequencing
1. Commit 1: Change 1 (reply_service.rb only) → push to
   `claude/test-cashout-bonus-features-mdfz0m` → DUMP with Render probe → Genius
   verifies + deploys (both Render services green).
2. Genius commits the corpus folder (PowerShell block).
3. Commit 2: Change 2 (new script only) → push → DUMP with the six run commands.
4. Genius runs steps 2→6 on Render; full-mode leak grader doubles as Change 1
   regression (expect zero leaks).

## Critical files
- `app/services/ai/reply_service.rb` — Change 1 (anchors: 189-198, 560-611, 2501-2518,
  2824-2859, 3494-3533)
- `script/patra_convo_replay_harness.rb` — Change 2 (NEW)
- `script/patra_money_harness.rb` — stub bundle / FakeClient / cleanup patterns to copy
- `script/patra_corpus_replay.rb` — graders, checkpoint, Tier-2 DeepSeek pattern to copy
- `app/services/games/conversation_orchestrator.rb` — read-only reference
