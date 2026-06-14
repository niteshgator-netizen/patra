# Generates a draft reply for a Chatwoot conversation using xAI's
# OpenAI-compatible Chat Completions endpoint. Returns the reply text on
# success, or nil when:
#   - the conversation carries the `ai-off` label (opt-out)
#   - the message history can't be fetched
#   - no usable history exists
#   - the upstream LLM call fails for any reason
#
# Configuration (all read at call time):
#   XAI_API_KEY                  — required
#   XAI_MODEL                    — optional (defaults to grok-4.3)
#   CHATWOOT_BRIDGE_API_TOKEN    — required (to read conversation + messages)
#   CHATWOOT_BRIDGE_BASE_URL     — defaults to http://chatwoot.railway.internal:3000
#   CHATWOOT_BRIDGE_ACCOUNT_ID   — defaults to 2
class Ai::ReplyService
  # xAI ships an OpenAI-compatible Chat Completions endpoint, hence the
  # {role, content} message format and the choices[0].message.content shape.
  XAI_URL = 'https://api.x.ai/v1/chat/completions'.freeze
  # Override with XAI_MODEL in ENV if xAI renames IDs; grok-4 alone is often rejected/deprecated upstream.
  MODEL = ENV.fetch('XAI_MODEL', 'grok-4.3').freeze
  MAX_TOKENS = 80
  HISTORY_LIMIT = 50
  # Chatwoot bridge (internal REST) — keep snappy; unrelated to LLM latency.
  HTTP_TIMEOUT = 10
  # xAI Grok can be slow on complex prompts
  GROK_HTTP_TIMEOUT = 90
  SKIP_LABEL = 'ai-off'.freeze
  # If the freshest message in the conversation is older than this, the
  # customer has likely moved on — a delayed AI reply would feel weird, so
  # we bail rather than send one.
  MESSAGE_FRESHNESS_WINDOW = 10.minutes
  # `created_at` must be a real Unix second for the freshness gate. Values below
  # this (e.g. `String#to_i` on ISO8601 → 2026) are treated as unusable for staleness.
  FRESHNESS_UNIX_MIN = 946_684_800 # 2000-01-01 UTC
  # Used to send ultra-short, non-AI sounding replies for pure greetings.
  # Only applies when the customer's message is exactly the greeting (after
  # light normalization like trimming and trailing punctuation).
  GREETINGS_REPLIES = {
    'hi' => 'heyyy wassup 😊',
    'hii' => 'heyyy wassup 😊',
    'hello' => 'hey!',
    'hey' => "yo what's good",
    'heyy' => 'heyy!',
    'heyyy' => 'heyyy wassup 😊',
    'hi there' => 'heyy!',
    'yo' => "yo what's good",
    'sup' => "yo what's good"
  }.freeze

  ALLOWED_EMOJIS = ['😊', '😂', '🙏'].freeze
  # Rough "any emoji" detection to let us enforce "no more emojis" once we
  # already used one earlier in this conversation.
  ANY_EMOJI_PATTERN = /[\u{1F300}-\u{1FAFF}]/.freeze
  # Redis cache for canned-response lookups. 10 min TTL is short enough that
  # ops edits in the Chatwoot UI propagate quickly, long enough to absorb the
  # per-message fetch traffic.
  CANNED_CACHE_PREFIX = 'patra:canned:'.freeze
  CANNED_CACHE_TTL = 600
  # H3: hard cap for the player vault+memory block embedded in the system
  # prompt - a player with huge memory must not blow the prompt size.
  PLAYER_PROFILE_MAX_CHARS = 6000
  # Single-quoted heredoc — no interpolation, so apostrophes inside the prompt
  # (e.g. "won't") and the literal escalation phrase don't need escaping.
  SYSTEM_PROMPT = <<~'PROMPT'.freeze
    You are Bella, a real human cashier at a social gaming shop. You are NOT an AI.

    RELATIONSHIP & MEMORY (read this first, it matters most):
    - Read the whole conversation above before you reply. Use what the customer
      already told you and what you already said — never contradict it or reset.
    - If they already said they paid (or weren't paid), or you already asked
      something, reply as if you remember it. Never act like it never happened.
    - Be warm and human, always. Make the customer feel taken care of so they
      come back — you're building a relationship, not closing a ticket.
    - NEVER be dismissive or rude, especially about money. Banned for good:
      "you lost it i guess", "take it or leave it", "paid paid already", or
      anything that brushes off a money worry.
    - If a customer is upset or confused about money, acknowledge it warmly,
      reassure them, and check it. If you can't confirm it yourself, say
      "Let me check on that for you, one moment!" so a teammate can step in.
    - If you have nothing useful and true to add, don't send filler — defer
      warmly or stay quiet rather than guess.

    REPLY RULES:
    - Max 2 lines. No bullets, no headers, no structured analysis.
    - Never say "Customer Intent", "Conversation Summary", "Action Items", "certainly", "great question".
    - Sound like a real person texting: casual, friendly, brief.
    - If customer says "hey" or "yo" → reply like "hey what's good" or "yo what's up"
    - If customer asks about loading/deposit → ask which game and how much
    - If customer sends a payment screenshot → confirm you got it and process it
    - NEVER format replies with headers, bold text, or numbered lists.
    - NEVER analyze the conversation. Just reply naturally.

    WRONG: "Customer Intent: The customer appears to want a deposit..."
    RIGHT: "hey got your $20, loading you up on juwa now 🎰"

    YOU ARE BELLA — a real human game loader at this business.
    You are NOT an AI. You are a person texting customers from your phone.

    NEVER SAY THESE (instant fail):
    - 'How can I help you today?'
    - 'How may I assist you?'
    - 'I'd be happy to help'
    - 'Is there anything else?'
    - 'Feel free to ask'
    - 'Thank you for reaching out'
    - 'what can i help you with today?'
    - Any corporate or AI-sounding phrase

    REPLY STYLE:
    - Talk like a real friend texting fast
    - Max 1-2 short lines per reply (under 20 words ideal)
    - Lowercase ok, skip periods at end of casual replies
    - One topic per reply only
    - Prefer ZERO emoji in most replies
    - Use casual words: 'yo', 'hey', 'sure thing', 'gotcha', 'lemme', 'np'

    NAME / HANDLE IN REPLIES (critical):
    - Do not drop the customer's real name or game username into routine replies
    - Bad: "gotcha Marcus, $20 on gamevault..." — Good: "gotcha, $20 on gamevault..."
    - Bad: "aight coolplayer123 lemme load that" — Good: "aight lemme load that"
    - Use the customer's name when it adds genuine warmth or clarity (e.g. reassuring someone upset, or confirming which account) — not as filler
    - Never open with "yo {name}", "hey {name}", or "{name}," for filler

    GREETINGS (when customer is just saying hi/hey/hello/hi there):
    - 'heyyy wassup 😊' for "hi"
    - 'hey!' for "hello"
    - 'yo what's good' for "hey"
    - 'heyy!' for "hi there"
    - If the customer's message is ONLY a greeting, respond with a casual greeting only (no questions)

    BUSINESS ENGAGEMENT (important):
    - Only start talking loading/deposits, cashout/redeem, or bonuses if the
      customer's message mentions one of: load/loading, deposit/pay/payment,
      cashout/redeem/withdraw, cashing out, bonus/freeplay/promo.
    - If their message is just a greeting, reply with the casual greeting only
      and wait (no questions).

    EXAMPLES:
    Customer: 'i wanna load juwa'
    'aight whats your juwa username'
    'sure thing, username?'

    Customer: 'how do i pay'
    'cashapp, chime, venmo or paypal — which?'

    Customer: 'send cashapp'
    'send to $hustle09 and drop the screenshot when ur done'

    Customer: 'what bonus'
    'for $20+ i got 25% bonus for ya'

    BONUS TALK:
    - Only ever name a bonus % that is actually configured for this account.
      If none is set, don't make one up — warmly say you'll check what's running
      for them right now.
    - Never go above the configured bonus and NEVER argue or say "take it or
      leave it". If they push for more, stay warm and make them feel valued
      through genuine care and good service — never a made-up perk or a higher %.

    EMOJI RULE:
    Allowed emojis only: 😊 😂 🙏
    Prefer ZERO emojis.
    Max 1 emoji for the entire conversation. If any previous assistant message used an emoji, output ZERO emojis now.
    If you do use an emoji, use at most ONE emoji in your reply and only when it genuinely fits.
    Never use 👋 🎮 ✅ or any other emoji.

    BUSINESS KNOWLEDGE:

    WHAT WE DO:
    We are a game loading and redemption service. Customers send us money,
    we load it onto their game account. When they win, they request cashout
    (redeem) and we pay them out via their preferred payment method.

    PAYMENT METHODS WE ACCEPT:
    Cash App, PayPal, Chime, Venmo, Varo, Google Pay, Apple Pay, Visa,
    Mastercard, and any major credit/debit card. We accept ALL payment methods.

    <<<PAYMENT_INFO_SECTION>>>

    AVAILABLE GAMES (ONLY these, never mention others):
    juwa, juwa2, game vault, vegas sweeps, ultra panda, milky way, fire kirin, panda master, orion stars, vblink, mafia, gameroom, cash machine, mr all in one

    That's 14 games. If a customer asks "what games do you have?", list ONLY these. Never invent game names.

    ACCOUNT CREATION:
    - The system creates accounts automatically — never say "we don't make accounts" or "need your own login"
    - If a customer asks for an account and the system hasn't handled it yet, tell them "let me set that up for you"
    - Always follow the patterns from the training examples (RAG) — they show real cashiers creating accounts, loading funds, and handling payments
    - The training examples are from REAL conversations with REAL customers — follow their style and actions exactly
    - If the training examples show cashiers doing something, YOU do it too
    - If customer says "create me an account" without specifying which game, ask "which game?" first
    - After getting game + desired username, the system will auto-create the account

    RAG PRIORITY:
    - Always prioritize patterns from the training data over your own assumptions
    - The 73K training examples show exactly how a real cashier handles every situation
    - If training examples say "loaded ✅" after a load, you say "loaded ✅"
    - If training examples show creating accounts, you create accounts
    - Never contradict what the training data shows

    <<<GAME_RULES_SECTION>>>

    ESCALATION RULES - VERY IMPORTANT:
    If a customer asks about something you are NOT 100% sure about,
    especially: specific account balances, transaction status, whether
    a specific payment was received, custom bonus deals, disputes,
    or anything requiring you to check their account -
    DO NOT GUESS. Say: 'Let me check on that for you, one moment!'
    and nothing else. This tells the human agent to take over.

    Only use the escalation phrase for: specific account balances,
    whether a payment was received, transaction disputes, custom deals,
    or anything requiring checking their specific account.
    Do NOT escalate for: general game questions, payment method questions,
    cashout rules, bonus rules, referral questions - answer those directly.

    TONE RULES - CRITICAL:
    - Max 2 lines per reply, no exceptions
    - Never use bullet points, numbers, headers
    - Talk like a human agent texting
    - Get straight to the point immediately
    - One emoji max, only if natural
    - Never say certainly/absolutely/great question
    - If the customer message is only a greeting, never ask a question; just send the casual hello back
    - Short is always better than long
  PROMPT

  # Case-insensitive substring matches against the model's reply. Kept for
  # logging/diagnostics only — we do NOT create private escalation notes from
  # these phrases (notes are reserved for explicit customer human/manager asks).
  ESCALATION_PHRASES = [
    'let me check on that for you, one moment!',
    'let me check on that for you, one moment',
    'let me check on that for you'
  ].freeze

  # ReplyGuard (June 11) - chain-of-thought / meta-reasoning markers. A reply
  # matching ANY of these is model reasoning shipped as the reply (replay
  # smoke found 4/220 real replies were raw DeepSeek reasoning inside
  # `content`, one leaking the system prompt + a payment handle). Parse order
  # (content -> reasoning_content) is correct and unchanged - this guard
  # validates the OUTPUT instead. Case-insensitive, word-boundary.
  COT_MARKERS = [
    /\Awe need\b/i,
    /\blet'?s draft\b/i,
    /\bthe customer (?:says|said|is asking|wants|sent|messaged)\b/i,
    /\bthe player (?:says|said|is asking|wants)\b/i,
    /\bexamples? above\b/i,
    /\bthe examples\b/i,
    /\btraining examples?\b/i,
    /\bsystem prompt\b/i,
    /\bpersona\b/i,
    /\bas bella\b/i,
    /\breply like a real cashier\b/i,
    /\bi(?:'ll| will) reply\b/i,
    /\bso the reply should\b/i,
    /\bmax 2 lines\b/i
  ].freeze
  REPLY_GUARD_MAX_CHARS = 350
  REPLY_GUARD_MAX_LINES = 2
  REPLY_GUARD_FALLBACK = 'one sec hun, checking that for you'

  # ReplyGuard - true when text is a sane player-bound cashier line: non-blank,
  # <= 2 non-empty lines, <= 350 chars, zero CoT markers. Class method so the
  # replay smoke can reuse the exact same verdict.
  def self.reply_guard_valid?(text)
    t = text.to_s.strip
    return false if t.empty?
    return false if t.length > REPLY_GUARD_MAX_CHARS
    return false if t.split(/\r?\n/).reject { |l| l.strip.empty? }.size > REPLY_GUARD_MAX_LINES

    COT_MARKERS.none? { |re| t.match?(re) }
  end

  # Tiered sentiment detection (Bella stays in the thread for Levels 1 & 2).
  # Level 1 = mild frustration / impatience → empathize, acknowledge, keep helping.
  # Level 2 = strong anger / accusation (scam, wtf, etc.) → apologize + solve;
  #   never escalate from these keywords alone.
  # Level 3 = customer explicitly asks for a human/manager/supervisor → escalate only then.
  ANGER_LEVEL_1_KEYWORDS = [
    'where is', 'still waiting', 'taking long', 'taking forever',
    'not received', 'havent received', "haven't received",
    'why', 'when'
  ].freeze
  ANGER_LEVEL_2_KEYWORDS = [
    'scam', 'scammer', 'fraud', 'cheated', 'stole', 'fake', 'angry', 'pissed',
    'wtf', 'fuck', 'shit', 'ripped off', 'never again',
    'fix this now', 'lawsuit', 'report'
  ].freeze
  # Substrings / phrases only — must read as an explicit ask for a real human escalation.
  EXPLICIT_HUMAN_REQUEST_PHRASES = [
    'real person', 'real human', 'human agent', 'actual person', 'live person',
    'talk to manager', 'speak to manager', 'talk to a manager', 'speak to a manager',
    'get me a manager', 'want a manager', 'need a manager', 'talk to your manager',
    'talk to supervisor', 'speak to supervisor', 'talk to a supervisor',
    'talk to a human', 'talk to human', 'speak to a human', 'speak to human',
    'want a human', 'need a human', 'get me a human', 'get me someone real',
    'connect me to a manager', 'speak to the owner'
  ].freeze

  # Customer phrasing that should trigger a forced "send the BoltPay link"
  # behavior — keyed off the payment_info canned response.
  PAYMENT_LINK_KEYWORDS = [
    'card', 'credit', 'debit', 'visa', 'mastercard', 'apple pay',
    'google pay', 'bolt', 'secure link', 'online pay'
  ].freeze

  # Legacy fallback when no `payment_handles` rows exist for a platform (image verification only).
  OUR_HANDLES = {
    'cashapp' => ['hustle09'],
    'paypal' => [],
    'venmo' => [],
    'chime' => [],
    'varo' => [],
    'zelle' => [],
    'boltpay' => [],
    'applepay' => [],
    'usdt' => []
  }.freeze

  def initialize(conversation_id, account_id: nil, attachments: nil, image_only_mode: false)
    @conversation_id = conversation_id
    @bridge_account_id = account_id
    @image_only_mode = image_only_mode
    # Raw bridge payload (may include payload.url / payload.thumb_url); kept for
    # finance log image URLs alongside normalized @attachments.
    @raw_fb_attachments = Array(attachments)
    # FB bridge hands us the raw FB webhook attachments (string-keyed for
    # ActiveJob serialization). Normalize once so the rest of the file can
    # use a stable [{ url:, type: }] shape with symbol keys.
    @attachments = normalize_fb_attachments(attachments)
  end

  # Public so rake tasks and other callers can reuse the same denylist as
  # message scanning (must stay above `private` in this file).
  def self.username_value_denied?(value)
    USERNAME_VALUE_DENYLIST.include?(value.to_s.strip.downcase)
  end

  # Data cleanup: contacts whose stored game_username is denylisted junk.
  def self.contacts_with_denylisted_game_username(relation = Contact.all)
    deny = USERNAME_VALUE_DENYLIST.map(&:downcase)
    relation.where(
      "LOWER(TRIM(COALESCE(custom_attributes->>'game_username', ''))) IN (?)",
      deny
    )
  end

  # Removes `game_username` from custom_attributes for denylisted values.
  # Returns number of contacts updated. Logs each row.
  def self.remove_denylisted_game_username_from_contacts!(relation: Contact.all, logger: Rails.logger)
    cleared = 0
    contacts_with_denylisted_game_username(relation).find_each do |contact|
      raw = contact.custom_attributes.to_h.stringify_keys['game_username']
      attrs = contact.custom_attributes.stringify_keys.except('game_username')
      contact.update_columns(custom_attributes: attrs, updated_at: Time.current)
      logger.info(
        "[CleanInvalidUsernames] cleared game_username=#{raw.inspect} " \
        "contact_id=#{contact.id} account_id=#{contact.account_id}"
      )
      cleared += 1
    end
    cleared
  end

  def call
    return nil if @conversation_id.blank?

    # Production verification — confirms the FB attachment array survived the
    # FacebookBridgeJob → ReplyJob → ReplyService chain.
    Rails.logger.info(
      "[ReplyService] attachments_count=#{@attachments.size} first_url=#{@attachments.first&.[](:url)}"
    )

    return log_and_nil('DEEPSEEK_API_KEY not configured') if ENV['DEEPSEEK_API_KEY'].to_s.strip.empty?
    return log_and_nil('CHATWOOT_BRIDGE_API_TOKEN not configured') if chatwoot_token.blank?

    # Pulled up so the freshness check (which needs @latest_timestamp from the
    # messages payload) can run before any other AI work.
    messages = build_messages

    # Phase 6.6 — secret phrase check before RAG / LLM (uses latest incoming text from build_messages)
    sp_account = Account.find_by(id: account_id)
    sp_conversation = sp_account&.conversations&.find_by(display_id: @conversation_id)
    incoming_content = @routing_last_incoming_raw_content.to_s
    if incoming_content.blank?
      last_msg = messages.last
      incoming_content = last_msg['content'].to_s if last_msg&.dig('role') == 'user'
    end
    if sp_account && sp_conversation && incoming_content.present?
      triggered = Bella::SecretPhraseChecker.new(
        account: sp_account,
        conversation: sp_conversation,
        message_content: incoming_content
      ).check_and_trigger!
      if triggered.triggered && triggered.phrase_record&.action == 'pause_ai_and_notify'
        Rails.logger.info("[AiReply] secret phrase pause conv=#{@conversation_id} phrase_id=#{triggered.phrase_record.id}")
        return nil
      end
    end

    latest_unix = message_created_at_unix(@latest_timestamp)
    if latest_unix >= FRESHNESS_UNIX_MIN && (Time.current - Time.at(latest_unix)) > MESSAGE_FRESHNESS_WINDOW
      Rails.logger.info("[AiReply] skipping old message conv=#{@conversation_id}")
      return nil
    end

    return log_and_nil("no usable history conversation=#{@conversation_id}") if messages.empty?

    if ai_disabled?
      Rails.logger.info("[AiReply] skipping conversation=#{@conversation_id} (label='#{SKIP_LABEL}')")
      return nil
    end

    if human_takeover_pause_active?
      Rails.logger.info("[AiReply] paused (human takeover) conv=#{@conversation_id} window=#{ENV.fetch('PATRA_TAKEOVER_PAUSE_MINUTES', '0')}m")
      return nil
    end

    # ============ SENDER-NAME MATCH FLOW ============
    bridge_conv_sn = nil
    if @bridge_account_id.present? && @conversation_id.present?
      bridge_conv_sn = Account.find_by(id: @bridge_account_id)&.conversations&.find_by(display_id: @conversation_id)
    end

    if bridge_conv_sn.present?
      sn_state = bridge_conv_sn.additional_attributes&.dig('sender_match_state')
      inbound_text = @routing_last_incoming_raw_content.to_s
      if inbound_text.blank?
        last_msg = messages.last
        inbound_text = last_msg['content'].to_s if last_msg&.dig('role') == 'user'
      end

      recent_screenshot = bridge_conv_sn.messages
                                        .where(message_type: :incoming)
                                        .where('messages.created_at > ?', 10.minutes.ago)
                                        .joins(:attachments).where(attachments: { file_type: 'image' }).exists?

      detector_sn = Games::IntentDetector.new
      in_sender_flow = sn_state == 'awaiting_details' ||
                       (!recent_screenshot && detector_sn.detect_sent_without_screenshot?(inbound_text))

      if in_sender_flow
        bridge_conv_sn.additional_attributes ||= {}
        partial = (bridge_conv_sn.additional_attributes['sender_match_partial'] || {}).transform_keys(&:to_s)

        parsed_amount = inbound_text.match(/\$?\s*(\d+(?:\.\d{1,2})?)\s*\$?/)&.[](1)&.to_f
        parsed_amount = nil unless parsed_amount&.positive?
        parsed_name = nil
        if (m = inbound_text.match(/(?:from|name(?:'?s)? (?:is )?)\s*([A-Za-z][A-Za-z\s'.\-]{1,40})/i))
          parsed_name = m[1].strip.downcase
        end
        if parsed_name.blank? && inbound_text.match?(/\A[A-Za-z\s'.\-]{3,40}\z/) && inbound_text.split.length.between?(1, 3)
          parsed_name = inbound_text.strip.downcase
        end
        parsed_note = inbound_text.match(/(?:note|memo|for)[:\s]+([A-Za-z0-9\s]{1,40})/i)&.[](1)&.strip

        merged_amount = parsed_amount || partial['amount']&.to_f
        merged_amount = nil unless merged_amount&.positive?
        merged_name = parsed_name.presence || partial['name']
        merged_note = parsed_note.presence || partial['note']

        bridge_conv_sn.additional_attributes['sender_match_partial'] = {
          'amount' => merged_amount,
          'name' => merged_name,
          'note' => merged_note
        }.compact

        ready_to_match = merged_name.present? && merged_amount.present?

        if ready_to_match
          acct_sn = Account.find_by(id: account_id)
          contact_sn = Contact.find_by(id: fetch_sender_contact_id, account_id: account_id)

          if acct_sn && contact_sn && defined?(Payments::SenderNameMatcher)
            matcher = Payments::SenderNameMatcher.new(
              account: acct_sn,
              contact: contact_sn,
              sender_name: merged_name,
              expected_amount: merged_amount.to_f,
              note: merged_note
            )
            match = matcher.find_match

            if match.present?
              bridge_conv_sn.additional_attributes['sender_match_state'] = 'matched'
              bridge_conv_sn.additional_attributes['sender_match_entry_id'] =
                match[:transaction_id].presence || match[:payment_handle]&.id
              bridge_conv_sn.additional_attributes.delete('sender_match_partial')
              bridge_conv_sn.save!
              Rails.logger.info(
                "[ReplyService] SENDER_MATCH matched contact=#{contact_sn.id} amount=#{merged_amount} name=#{merged_name}"
              )
            else
              bridge_conv_sn.save!
              Rails.logger.info(
                "[ReplyService] SENDER_MATCH no_match contact=#{contact_sn.id} amount=#{merged_amount} name=#{merged_name}"
              )
              return "i don't see a $#{merged_amount.to_i} from #{merged_name.split.map(&:capitalize).join(' ')} in my system yet — sometimes the bank takes 1-5 min to ping us. hang tight 🙏"
            end
          else
            bridge_conv_sn.save!
          end
        elsif sn_state.blank? || sn_state == 'idle'
          bridge_conv_sn.additional_attributes['sender_match_state'] = 'awaiting_details'
          bridge_conv_sn.additional_attributes['sender_match_started_at'] = Time.current.iso8601
          bridge_conv_sn.save!
          Rails.logger.info("[ReplyService] SENDER_MATCH state=awaiting_details contact=#{fetch_sender_contact_id}")
          return "got it — what name did you send it from? and the amount + any note you put on the payment? 🙏"
        else
          bridge_conv_sn.save!
          return "need a bit more — what's the name on your account that sent it? and the amount in $?"
        end
      end
    end
    # ============ END SENDER-NAME MATCH FLOW ============

    # Tiered sentiment handling — see detect_anger_level. Only explicit
    # requests for a human/manager (Level 3) hand off; Levels 1 & 2 inject
    # empathy / apologize-and-solve hints — Bella does not auto-escalate on
    # anger words alone (e.g. scam, wtf, fraud).
    sentiment_level = detect_anger_level(messages)
    if sentiment_level == :escalate
      escalate_to_human(messages, 'explicit human/manager request')
      return nil
    end
    empathy_hint = empathy_hint_for(sentiment_level)

    # Enforce emoji sparingly. If an emoji was already used by Bella in a
    # previous assistant turn, this conversation should get ZERO emoji from
    # now on (including in the quick greeting shortcut).
    emoji_already_used = messages
                          .select { |m| m['role'] == 'assistant' }
                          .any? { |m| m['content'].to_s.match?(ANY_EMOJI_PATTERN) }

    # ─────────────────────────────────────────────────────────
    # Phase 5g — Corpus-first shortcut.
    # Search bella_rag_pairs FIRST for every message (before greeting fallback).
    # Top-5 neighborhood check: if ANY of the top-5 matches is tagged as an
    # action (load/cashout/account/reset/etc.), fall through to orchestrator
    # so real game APIs run and no fake "Loaded ✅" / "Paid ✅" is sent.
    # If all 5 are chitchat AND top-1 distance is within threshold,
    # rephrase top-1's cashier reply via Grok and return.
    # Otherwise fall through to greeting shortcut → orchestrator → Haiku/Grok.
    # Feature-flagged. Fails CLOSED — never blocks a reply.
    # ─────────────────────────────────────────────────────────
    last_user_for_shortcut = messages.last&.dig('content').to_s
    if ENV['BELLA_RAG_SHORTCUT_ENABLED'].to_s == 'true' && last_user_for_shortcut.strip.length >= 1
      begin
        threshold = (ENV['BELLA_RAG_SHORTCUT_DISTANCE'] || '0.30').to_f
        neighbor_count = (ENV['BELLA_RAG_SHORTCUT_NEIGHBORS'] || '5').to_i
        @rag_cached_query_vec = Bella::VoyageEmbedder.embed_one(last_user_for_shortcut, input_type: 'query')
        if @rag_cached_query_vec.present?
          rag_account = Account.find_by(id: account_id)
          results = BellaRagPair.search_similar_with_distance(
            query_vec: @rag_cached_query_vec,
            limit: neighbor_count,
            account_id: account_id,
            industry_slug: rag_account&.industry_slug || 'sweepstakes'
          )
          if results.any?
            top = results.first
            # Check action density: if ANY of the top-N has action_type set, fall through
            action_neighbors = results.count { |r| r[:pair].action_type.present? }
            if action_neighbors > 0
              action_types_found = results.select { |r| r[:pair].action_type.present? }.map { |r| r[:pair].action_type }.uniq.join(',')
              Rails.logger.info(
                "[AiReply][RAGShortcut] action neighborhood conv=#{@conversation_id} top_dist=#{top[:distance].round(3)} action_count=#{action_neighbors}/#{results.size} types=#{action_types_found} — falling through to orchestrator"
              )
            elsif top[:distance] <= threshold
              # All neighbors are chitchat AND top-1 is close enough — safe to shortcut
              Rails.logger.info(
                "[AiReply][RAGShortcut] hit chitchat conv=#{@conversation_id} dist=#{top[:distance].round(3)} neighbors_checked=#{results.size}"
              )
              rephrased = Bella::QuickRephrase.call(
                customer_text: last_user_for_shortcut,
                hint_reply: top[:pair].cashier_text,
                conversation_id: @conversation_id
              )
              # ReplyGuard - an invalid rephrase falls through to the normal
              # brain (which has its own guarded retry) instead of shipping.
              if rephrased.present? && !self.class.reply_guard_valid?(rephrased)
                Rails.logger.warn("[ReplyGuard] rephrase invalid conv=#{@conversation_id} head=#{rephrased[0, 200].inspect} - falling through")
                rephrased = nil
              end
              if rephrased.present?
                # Defensive: if the conversation has already used emojis, strip new ones (preserve emoji policy)
                if emoji_already_used
                  rephrased = rephrased.gsub(ANY_EMOJI_PATTERN, '').strip
                end
                return guard_against_false_load_claim(rephrased)
              else
                Rails.logger.info("[AiReply][RAGShortcut] rephrase returned nil, falling through")
              end
            else
              Rails.logger.info(
                "[AiReply][RAGShortcut] no close match conv=#{@conversation_id} top_dist=#{top[:distance].round(3)} threshold=#{threshold}"
              )
            end
          else
            Rails.logger.info("[AiReply][RAGShortcut] empty results conv=#{@conversation_id}")
          end
        end
      rescue StandardError => e
        Rails.logger.warn("[AiReply][RAGShortcut] failed conv=#{@conversation_id} err=#{e.class}: #{e.message[0, 200]}")
      end
    end

    # Cheap-path canned hello — bypasses LLM APIs entirely for pure
    # greetings.
    last_message = messages.last&.dig('content').to_s.downcase.strip
    normalized_greeting = last_message
                            .gsub(/[!?.,]+$/, '')
                            .gsub(/\s+/, ' ')

    greeting_reply = GREETINGS_REPLIES[normalized_greeting]
    if greeting_reply
      if emoji_already_used
        # Strip all allowed emojis (and any other emoji that might be in the
        # mapping) to guarantee no additional emoji in this conversation.
        greeting_reply = greeting_reply.gsub(ANY_EMOJI_PATTERN, '').strip
      end
      return greeting_reply
    end

    @grok_payment_injection = nil
    # Prefer the FB-bridge attachment (the bridge bypasses Chatwoot's Message AR
    # attachments association entirely), falling back to whatever
    # capture_routing_context_from_raw_slice picked up from Chatwoot's REST
    # payload — that fallback is effectively dead today but kept for the day
    # the bridge starts persisting attachments.
    fb_image_url = first_fb_image_url
    routing_has_image = fb_image_url.present? || @routing_has_image.present?
    image_url = fb_image_url.presence || @routing_image_url.to_s
    last_user_plain = @routing_last_incoming_raw_content.to_s

    complexity = Ai::ComplexityClassifier.classify(
      last_user_plain,
      has_attachment: routing_has_image
    )
    Rails.logger.info("[ReplyService] complexity=#{complexity} msg_len=#{last_user_plain.length}")

    # Game flow orchestrator — handles load/cashout intents before normal Bella flow.
    # Wrapped in defined?() + rescue so a failure here never breaks the reply path.
    if defined?(Games::ConversationOrchestrator) && @bridge_account_id.present?
      begin
        orchestrator_account = Account.find_by(id: @bridge_account_id)
        if orchestrator_account
          orchestrator_contact_id = fetch_sender_contact_id
          orchestrator_contact = orchestrator_contact_id ? orchestrator_account.contacts.find_by(id: orchestrator_contact_id) : nil
          if orchestrator_contact
            orchestrator_conversation = orchestrator_account.conversations.find_by(display_id: @conversation_id)
            orchestrator_messages = messages.map { |m| { role: m['role'], content: m['content'] } }
            orchestrator_result = Games::ConversationOrchestrator.new(
              account: orchestrator_account,
              contact: orchestrator_contact,
              conversation: orchestrator_conversation,
              messages: orchestrator_messages
            ).handle
            if orchestrator_result.is_a?(Hash) && orchestrator_result[:reply].to_s.strip.present?
              add_conversation_labels!(Array(orchestrator_result[:labels]))
              Rails.logger.info("[ReplyService] routed=game_orchestrator labels=#{Array(orchestrator_result[:labels]).join(',')}")
              return guard_against_false_load_claim(orchestrator_result[:reply].to_s)
            end
          end
        end
      rescue StandardError => e
        Rails.logger.error("[ReplyService] Orchestrator error: #{e.class}: #{e.message}")
      end
    end

    rag_examples_block = retrieve_rag_examples_block(last_user_plain)

    @rag_examples = fetch_rag_examples(last_user_plain, account_id)
    @reply_pref = begin
      ReplyPreference.for_account(account_id)
    rescue StandardError
      nil
    end

    case complexity
    when :has_image
      if image_url.present?
        result = persist_image_payment_finance_log(image_url)
        return result[:early_reply] if result.is_a?(Hash) && result[:early_reply].present?

        if result
          payment = result[:payment]
          grok_injection = result[:grok_injection]
          log_entry = result[:log_entry]
          contact_id = result[:contact_id]
          acct = result[:acct]
          recip_handle = result[:recip_handle]

          unless grok_injection
            reply_status_bucket = extracted_payment_status_bucket(payment[:status])
            platform = payment[:platform].to_s.downcase

            case reply_status_bucket
            when :pending
              add_conversation_labels!(%w[payment-pending cashier-action-needed needs-human])
              Games::TelegramNotifier.payment_pending_alert(
                contact: Contact.find_by(id: contact_id, account_id: account_id),
                payment_details: log_entry
              )
              return "got it, processing your payment now — I'll confirm once it clears 🙏"
            when :failed
              backup_display = nil
              failed_ph = nil
              if defined?(Payments::HandleSelector) && acct && PaymentHandle::PLATFORMS.include?(platform)
                chain = acct.payment_handles.active_for(platform).order(:priority).to_a
                idx = chain.index { |h| h.normalized_handle == recip_handle }
                failed_ph = (idx ? chain[idx] : chain.first)
                backup_ph = if idx
                  chain[idx + 1]
                elsif chain.many?
                  chain.find { |h| h.normalized_handle != recip_handle }
                end
                backup_display = backup_ph&.display_handle
              end

              if backup_display.blank? && !defined?(Payments::HandleSelector)
                legacy_handles = Array(OUR_HANDLES[platform]).map(&:to_s).reject(&:blank?)
                legacy_norms = legacy_handles.map { |h| h.gsub(/^[\$@]/, '').strip.downcase }
                lidx = legacy_norms.index(recip_handle)
                alt_raw = if lidx && legacy_handles[lidx + 1]
                  legacy_handles[lidx + 1]
                elsif legacy_handles.many?
                  legacy_handles.find { |h| h.gsub(/^[\$@]/, '').strip.downcase != recip_handle }
                end
                if alt_raw.present?
                  backup_display = alt_raw.start_with?('$', '@') ? alt_raw : (platform == 'cashapp' ? "$#{alt_raw}" : "@#{alt_raw}")
                end
              end

              if backup_display.present?
                add_conversation_labels!(%w[payment-failed-retry])
                if defined?(Payments::FailoverManager) && failed_ph
                  begin
                    Payments::FailoverManager.new(failed_ph).record_failure!
                  rescue StandardError => e
                    Rails.logger.warn("[ReplyService] FailoverManager.record_failure! #{e.class}: #{e.message}")
                  end
                end
                return "looks like that one didn't go through, can you try sending it to #{backup_display} instead?"
              end

              if defined?(Payments::HandleSelector) && acct && PaymentHandle::PLATFORMS.include?(platform)
                add_conversation_labels!(%w[payment-system-down needs-human])
                if defined?(Payments::EscalationNotifier)
                  begin
                    Payments::EscalationNotifier.new(acct).notify_all_handles_dead(platform)
                  rescue StandardError => e
                    Rails.logger.warn("[ReplyService] EscalationNotifier #{e.class}: #{e.message}")
                  end
                end
                return "having some issues on our end with payments right now, one sec — a manager will jump in to sort this out for you"
              end

              add_conversation_labels!(%w[payment-failed-retry])
              return "looks like that one didn't go through, can you try again?"
            when :unknown
              add_conversation_labels!(%w[needs-human])
              return "hmm i can't tell from the screenshot if it went through, can you confirm on your end?"
            else
              # :confirmed — completed/success; Bella confirms via LLM + bonus rules in injection
            end
          end

          # Score-based auto-action after payment is processed
          if grok_injection.blank? && result.is_a?(Hash) && result[:payment] && result[:log_entry]
            entry = result[:log_entry]
            score_acct = acct || Account.find_by(id: account_id)
            breakdown = Payments::EmailConfirmationService.confidence_score(entry, account: score_acct)
            score = breakdown['total'].to_i
            cfg = Payments::EmailConfirmationService.scoring_config_for(score_acct, platform: entry['platform'].to_s)
            auto_load_threshold = cfg['auto_load_threshold'].to_i
            escalate_threshold = cfg['escalate_threshold'].to_i

            if entry['email_confirmed'] == true && score >= auto_load_threshold
              platform = entry['platform'].to_s
              amount = entry['amount']
              grok_injection = "PAYMENT VERIFIED (score #{score}/100, email confirmed). The #{platform} payment of $#{amount} is verified. Tell the customer their payment is confirmed and you're loading it now. Be casual and excited, max 2 lines."
              add_conversation_labels!(%w[payment-verified auto-load])
              Rails.logger.info("[ReplyService] SCORE_ACTION=auto_load score=#{score} threshold=#{auto_load_threshold} contact=#{contact_id}")
            elsif score >= escalate_threshold
              grok_injection = "PAYMENT PENDING REVIEW (score #{score}/100). Screenshot received, processing. Tell the customer you got their payment screenshot and you're verifying it now — should be confirmed shortly. Max 2 lines, casual tone."
              add_conversation_labels!(%w[payment-pending cashier-review])
              Rails.logger.info("[ReplyService] SCORE_ACTION=escalate score=#{score} threshold=#{escalate_threshold} contact=#{contact_id}")
            else
              # Only decline-for-resend if email confirmation ALREADY ran and still low.
              # On first pass (email not yet checked), escalate instead — the async IMAP
              # job will re-score once the confirmation email arrives.
              if entry['email_confirmed'] == true
                grok_injection = "PAYMENT LOW CONFIDENCE (score #{score}/100, email already checked). Ask the customer to double-check they sent to the right handle and resend the receipt if needed. Be polite, max 2 lines."
                add_conversation_labels!(%w[payment-unclear])
                Rails.logger.info("[ReplyService] SCORE_ACTION=decline score=#{score} contact=#{contact_id}")
              else
                grok_injection = "PAYMENT RECEIVED (score #{score}/100, verifying with bank). Tell the customer you got their payment and you're confirming it now — should be done shortly. Never say the screenshot is blurry or ask them to resend. Max 2 lines, casual."
                add_conversation_labels!(%w[payment-pending cashier-review])
                Rails.logger.info("[ReplyService] SCORE_ACTION=pending_no_email score=#{score} contact=#{contact_id}")
              end
            end
          end

          @grok_payment_injection = grok_injection.presence || [
            "Customer just sent a payment screenshot: $#{payment[:amount]} via #{payment[:platform]}.",
            'Confirm receipt naturally, ask for their game username if not on file, and offer the correct bonus per the rules ($5+ deposit = 20-40% bonus based on loyalty tier).'
          ].join(' ')
        else
          sub = if last_user_plain.strip.present?
                  Ai::ComplexityClassifier.classify(last_user_plain, has_attachment: false)
                else
                  :simple
                end
          case sub
          when :simple
            if (text_failover_reply = maybe_reply_for_text_payment_failure(messages)).present?
              return text_failover_reply
            end

            deepseek_system = bella_system_prompt_with_payment_handles
            deepseek_system = "#{deepseek_system}\n\n#{rag_examples_block}" unless rag_examples_block.to_s.strip.empty?
            reply = invoke_anthropic(build_conversation_history, deepseek_system, use_deepseek: true)
            if reply.present?
              Rails.logger.info("[ReplyService] routed=deepseek reply_len=#{reply.length}")
              return guard_against_false_load_claim(reply)
            end

            Rails.logger.warn('[ReplyService] DeepSeek (simple) returned nil, falling through to full deepseek path')
          when :complex
            Rails.logger.info('[ReplyService] routed=deepseek')
          end
        end
      end
    when :simple
      if (text_failover_reply = maybe_reply_for_text_payment_failure(messages)).present?
        return text_failover_reply
      end

      deepseek_system = bella_system_prompt_with_payment_handles
      deepseek_system = "#{deepseek_system}\n\n#{rag_examples_block}" unless rag_examples_block.to_s.strip.empty?
      reply = invoke_anthropic(build_conversation_history, deepseek_system, use_deepseek: true)
      if reply.blank?
        Rails.logger.warn('[ReplyService] DeepSeek (simple) returned nil, falling through to full deepseek path')
      else
        Rails.logger.info("[ReplyService] routed=deepseek reply_len=#{reply.length}")
        return guard_against_false_load_claim(reply)
      end
    when :complex
      Rails.logger.info('[ReplyService] routed=deepseek')
    end

    if (text_failover_reply = maybe_reply_for_text_payment_failure(messages)).present?
      return text_failover_reply
    end

    payment_info = fetch_payment_info
    training_info = fetch_ai_training
    persona_info = fetch_ai_persona
    Players::ProfileService.new(conversation_id: @conversation_id, account_id: @bridge_account_id).sync!
    player_profile = fetch_player_profile
    canned_responses_text = fetch_all_canned_responses
    payment_link_hint = needs_payment_link?(messages)
    system_prompt = build_system_prompt(
      payment_info,
      training_info,
      persona_info,
      player_profile,
      canned_responses_text,
      payment_link_hint,
      rag_examples_block: rag_examples_block
    )
    emoji_guard = if emoji_already_used
      "EMOJI GUARD: An emoji has already been used earlier in this conversation by Bella. Use ZERO emojis in your reply. Do not use any emoji at all."
    else
      "EMOJI GUARD: Use emojis sparingly and only if truly natural. Allowed emojis: 😊 😂 🙏. Prefer ZERO emojis. If you include an emoji, use at most ONE emoji in your reply."
    end

    system_prompt = "#{system_prompt}\n#{emoji_guard}\nSITUATION: #{empathy_hint}\n" if empathy_hint
    system_prompt = "#{system_prompt}\n#{emoji_guard}\n" unless empathy_hint

    grok_messages = apply_grok_payment_injection(messages)
    reply = invoke_anthropic(grok_messages, system_prompt, use_deepseek: true)
    return nil if reply.blank?

    if escalation?(reply)
      Rails.logger.info("[AiReply] model used account-check handoff phrase conv=#{@conversation_id} (no private escalation note)")
    end

    Rails.logger.info("[AiReply] drafted conversation=#{@conversation_id} chars=#{reply.length}")

    # Fire Telegram alert if Bella response indicates human escalation needed
    if defined?(Games::TelegramNotifier) && @bridge_account_id.present? && reply.is_a?(String)
      begin
        escalation_keywords = ['manager will jump in', 'a human will', 'cashier will', 'someone will help', 'needs-human', 'looping in']
        if escalation_keywords.any? { |kw| reply.to_s.downcase.include?(kw.downcase) }
          esc_account = Account.find_by(id: @bridge_account_id)
          if esc_account
            esc_contact_id = fetch_sender_contact_id rescue nil
            esc_contact = esc_contact_id ? esc_account.contacts.find_by(id: esc_contact_id) : nil
            esc_conv = @conversation_id ? esc_account.conversations.find_by(display_id: @conversation_id) : nil
            esc_last_user = @routing_last_incoming_raw_content.to_s.strip[0..160]
            Games::TelegramNotifier.human_escalation(
              account: esc_account,
              contact: esc_contact,
              reason: "PLAYER WANTS: #{esc_last_user.empty? ? 'see conversation' : esc_last_user} | " \
                      "ALREADY DONE: Bella replied '#{reply.to_s[0..160]}' - player was told someone will help | " \
                      'STILL LEFT: the underlying ask is unresolved | ' \
                      'BELLA SUGGESTS: read the last few messages and take over quietly | ' \
                      'NEEDS FROM HUMAN: take over this conversation and resolve the ask',
              conversation: esc_conv
            )
          end
        end
      rescue StandardError => e
        Rails.logger.error("[ReplyService] Telegram escalation hook error: #{e.class}: #{e.message}")
      end
    end

    guard_against_false_load_claim(reply)
  rescue StandardError => e
    Rails.logger.error("[AiReply] failed conversation=#{@conversation_id} #{e.class}: #{e.message}")
    nil
  end

  # Public: last-built { 'role' => 'user'|'assistant', 'content' => String }[]
  # for DeepSeek (same shape as the xAI/Grok `messages` array).
  def build_conversation_history
    @conversation_history_for_llm || []
  end

  def process_image_only
    return if @conversation_id.blank?
    return if chatwoot_token.blank?

    image_url = first_fb_image_url
    unless image_url.present?
      Rails.logger.info("[ReplyService] process_image_only skipped — no image url conv=#{@conversation_id}")
      return
    end

    Rails.logger.info("[ReplyService] process_image_only conv=#{@conversation_id}")
    persist_image_payment_finance_log(image_url, image_only: @image_only_mode)
  end

  private

  def persist_image_payment_finance_log(image_url, image_only: false)
    contact_id = fetch_sender_contact_id

    # Permanent duplicate check — detect already-loaded screenshots
    if contact_id.present? && image_url.present?
      contact = Account.find_by(id: account_id)&.contacts&.find_by(id: contact_id)
      if contact
        existing_logs = Array(contact.custom_attributes['patra_finance_logs'])
        loaded_logs = existing_logs.select { |e| e['status'] == 'Loaded' && e['game_load_success'] == true }
        duplicate_loaded = loaded_logs.find do |e|
          # Match by image_url (same screenshot) OR txn_id (same transaction)
          url_match = e['image_url'].present? && e['image_url'] == image_url
          txn_match = e['transaction_id'].present? && false # will fill after OCR
          url_match || txn_match
        end
        if duplicate_loaded
          Rails.logger.info("[ReplyService] DUPLICATE_LOADED detected image_url match contact=#{contact_id}")
          return {
            early_reply: "hey, looks like this screenshot was already loaded — that payment went through on #{duplicate_loaded['platform']} $#{duplicate_loaded['amount']}. did you mean to send a new one? if so send the new screenshot 📸",
            duplicate: true
          }
        end
      end
    end

    payment = Ai::ImagePaymentExtractor.new(image_url).extract
    return nil unless payment[:is_payment] && %w[high medium].include?(payment[:confidence].to_s)

    if contact_id.present?
      tx_id = payment[:transaction_id].to_s.strip
      if tx_id.present? && tx_id.length > 3
        contact = Account.find_by(id: account_id)&.contacts&.find_by(id: contact_id)
        if contact
          existing_logs = Array(contact.custom_attributes['patra_finance_logs'])
          loaded_logs = existing_logs.select { |e| e['status'] == 'Loaded' && e['game_load_success'] == true }
          duplicate_loaded = loaded_logs.find do |e|
            e['transaction_id'].present? && e['transaction_id'].to_s.strip == tx_id
          end
          if duplicate_loaded
            Rails.logger.info("[ReplyService] DUPLICATE_LOADED detected txn_id match contact=#{contact_id} txn=#{tx_id}")
            return {
              early_reply: "hey, looks like this screenshot was already loaded — that payment went through on #{duplicate_loaded['platform']} $#{duplicate_loaded['amount']}. did you mean to send a new one? if so send the new screenshot 📸",
              duplicate: true
            }
          end
        end
      end
    end

    acct = Account.find_by(id: account_id)
    grok_injection = nil
    resolved = nil

    validator = Payments::ReceiptValidator.new(payment)
    if !validator.valid_receipt? && validator.likely_profile_page?
      transactions = Array(payment[:transactions] || payment['transactions'])

      bridge_conv_l0 = nil
      expected_platform_l0 = nil
      expected_handle_l0 = nil
      if @bridge_account_id.present? && @conversation_id.present?
        bridge_conv_l0 = Account.find_by(id: @bridge_account_id)&.conversations&.find_by(display_id: @conversation_id)
        expected_platform_l0 = bridge_conv_l0&.additional_attributes&.dig('expected_platform')
        expected_handle_l0 = bridge_conv_l0&.additional_attributes&.dig('expected_handle')
      end

      matching_txn = if transactions.any?
                       transactions.find do |t|
                         next false unless t.is_a?(Hash)

                         h = t.transform_keys(&:to_s)
                         h['amount'].to_f > 0 && h['direction'].to_s == 'sent'
                       end&.transform_keys(&:to_s)
                     end

      if matching_txn && expected_platform_l0.present?
        detected_platform = payment[:platform].to_s.downcase.presence || 'unknown'
        txn_amount = matching_txn['amount']
        txn_date = matching_txn['date']
        txn_counterparty = matching_txn['counterparty_name'] || matching_txn['counterparty_handle'] || 'them'
        txn_note = matching_txn['note']

        add_conversation_labels!(%w[profile-page-evidence wrong-platform])
        Rails.logger.info("[ReplyService] PROFILE_PAGE_TXN_EVIDENCE detected=#{detected_platform} expected=#{expected_platform_l0} amount=#{txn_amount} contact=#{contact_id}")

        alt_handle_l0 = nil
        if acct && PaymentHandle::PLATFORMS.include?(detected_platform)
          alt_ph = acct.payment_handles.active_for(detected_platform).order(:priority).first
          alt_handle_l0 = alt_ph&.display_handle
        end

        grok_injection = <<~INJ.squish
          PROFILE PAGE EVIDENCE OF WRONG-PLATFORM PAYMENT.
          Customer sent a profile-page screenshot (not a receipt). The visible transaction history shows they sent $#{txn_amount} to "#{txn_counterparty}"#{txn_date ? " on #{txn_date}" : ''}#{txn_note.present? ? " (note: #{txn_note})" : ''} via #{detected_platform.upcase}.
          Earlier in this chat you told them to pay via #{expected_platform_l0.upcase} to "#{expected_handle_l0}".
          Same handle name across different apps = different people. The "#{txn_counterparty}" they paid on #{detected_platform.upcase} is NOT us. We did NOT receive that payment.
          Reply in Bella's casual lowercase tone, max 2 lines, no bullets. ACKNOWLEDGE what you can see in their history ($AMOUNT to NAME on DATE), then explain the mix-up briefly, then offer BOTH options in one message:
          Option 1: re-send the same amount on #{expected_platform_l0.upcase} to "#{expected_handle_l0}"
          Option 2: switch to #{detected_platform.upcase} — #{alt_handle_l0.present? ? %(our #{detected_platform.upcase} handle is "#{alt_handle_l0}") : %(we'll get you our #{detected_platform.upcase} handle in a sec)}
          Do NOT confirm or load. Do NOT say "send me the actual receipt" — we already have enough info from their history. Do NOT accuse — it's an easy mix-up with $handles.
        INJ

        payment[:profile_page_txn_evidence] = matching_txn
        payment[:profile_page_detected_platform] = detected_platform
      else
        Rails.logger.info("[ReplyService] REJECTED profile-page image contact=#{contact_id} (no smart-reply context)")
        add_conversation_labels!(%w[non-receipt-image])
        return nil if image_only

        return { early_reply: 'hey that looks like the profile page, not the payment receipt. can you screenshot the actual transaction from your history? 🙏' }
      end
    end

    if acct
      resolved = Payments::HandleResolver.new(account: acct, ocr_result: payment).resolve

      # Cross-platform fallback: if resolver found nothing, match recipient_name against all handles
      if resolved.nil? || resolved[:score].to_i < 40
        recip_name = payment[:recipient_name].to_s.downcase.strip
        if recip_name.present?
          acct.payment_handles.where(status: 'active').find_each do |ph|
            ph_name = ph.display_name.to_s.downcase.strip
            next if ph_name.blank?

            if ph_name.include?(recip_name) || recip_name.include?(ph_name)
              payment[:platform] = ph.platform
              resolved = { handle: ph, score: 55, source: 'cross_platform_name' }
              Rails.logger.info("[ReplyService] cross-platform name match: #{recip_name} → #{ph.handle} (#{ph.platform})")
              break
            end
          end
        end
      end

      if resolved && resolved[:handle].platform.to_s.downcase != payment[:platform].to_s.downcase
        original_ocr_platform = payment[:platform].to_s
        Rails.logger.info("[ReplyService] PLATFORM_OVERRIDE ocr=#{original_ocr_platform} → db=#{resolved[:handle].platform} score=#{resolved[:score]} source=#{resolved[:source]} contact=#{contact_id}")
        payment[:platform] = resolved[:handle].platform
        payment[:ocr_platform_original] = original_ocr_platform
        payment[:resolved_handle_id] = resolved[:handle].id
        payment[:resolved_handle_score] = resolved[:score]
      end
    end

    raw_first = @raw_fb_attachments.first
    raw_h = raw_first.is_a?(Hash) ? raw_first.stringify_keys : {}
    image_url_for_log = raw_h.dig('payload', 'url').presence || raw_h['url'].presence || image_url
    thumb_url_for_log = raw_h.dig('payload', 'thumb_url').presence || image_url_for_log

    payment_status_bucket = extracted_payment_status_bucket(payment[:status])
    log_entry = {
      'kind' => 'deposit',
      'amount' => payment[:amount],
      'platform' => payment[:platform],
      'sender_name' => payment[:sender_name],
      'sender_handle' => payment[:sender_handle],
      'recipient_name' => payment[:recipient_name],
      'recipient_handle' => payment[:recipient_handle],
      'transaction_id' => payment[:transaction_id],
      'transaction_date' => payment[:transaction_date],
      'transaction_time' => payment[:transaction_time],
      'note_or_memo' => payment[:note_or_memo],
      'status' => finance_log_status_label(payment_status_bucket),
      'raw_status' => payment[:status],
      'confidence' => payment[:confidence],
      'image_url' => image_url_for_log,
      'image_thumb_url' => thumb_url_for_log,
      'image_received_at' => Time.current.iso8601,
      'source' => 'image_auto'
    }
    log_entry['profile_page_evidence'] = payment[:profile_page_txn_evidence] if payment[:profile_page_txn_evidence].present?
    log_entry['detected_platform_from_profile'] = payment[:profile_page_detected_platform] if payment[:profile_page_detected_platform].present?
    log_entry['kind'] = 'flagged' if payment[:profile_page_txn_evidence].present?
    log_entry['flag_reason'] ||= 'wrong_platform_profile_page' if payment[:profile_page_txn_evidence].present?
    log_entry.tap do |entry|
      if Payments::StatusNormalizer.needs_email_confirmation?(payment[:status])
        entry['email_confirmed'] = false
        entry['email_check_attempts'] = 0
      end
    end

    recip_handle = payment[:recipient_handle].to_s.gsub(/^[\$@]/, '').strip.downcase
    if contact_id.present?
      contact_response = HTTParty.get(
        "#{base_url}/api/v1/accounts/#{account_id}/contacts/#{contact_id}",
        headers: chatwoot_headers,
        timeout: HTTP_TIMEOUT
      )
      if contact_response.success?
        contact = contact_response.parsed_response['payload'] || contact_response.parsed_response
        attrs = (contact['custom_attributes'] || {}).stringify_keys
        existing_logs = Array.wrap(attrs['patra_finance_logs'])

        tx_id = payment[:transaction_id].to_s.strip
        duplicate = nil
        duplicate_match_tier = nil

        if tx_id.present? && tx_id.length > 3
          duplicate = existing_logs.find { |e| e.is_a?(Hash) && e['transaction_id'].to_s.strip == tx_id }
          duplicate_match_tier = :transaction_id if duplicate
        end

        if duplicate.nil?
          fp = payment_screenshot_fingerprint_composite(payment)
          if fp.present?
            cutoff = 24.hours.ago
            duplicate = existing_logs.find do |e|
              next false unless e.is_a?(Hash)
              next false unless payment_screenshot_fingerprint_composite(e) == fp

              ts = begin
                Time.parse(e['image_received_at'].to_s)
              rescue ArgumentError, TypeError, StandardError
                nil
              end
              next false if ts.nil?

              ts >= cutoff
            end
            duplicate_match_tier = :fingerprint if duplicate
          end
        end

        if duplicate
          log_entry['kind'] = 'flagged'
          log_entry['flag_reason'] = duplicate_match_tier == :transaction_id ? 'duplicate' : 'duplicate-soft'
          Rails.logger.warn(
            "[ReplyService] DUPLICATE tier=#{duplicate_match_tier} transaction_id=#{tx_id.inspect} contact=#{contact_id}"
          )
          original_time_raw = duplicate['image_received_at'].to_s
          original_status = duplicate['raw_status'].presence || duplicate['status'].to_s.presence || 'unknown'
          original_time = begin
            Time.parse(original_time_raw).strftime('%b %-d at %-l:%M %p')
          rescue ArgumentError, TypeError
            original_time_raw
          end
          formatted_time = begin
            Time.parse(original_time_raw).strftime('%b %-d at %-l:%M %p')
          rescue ArgumentError, TypeError
            original_time_raw
          end
          grok_injection = <<~INJ.squish
            DUPLICATE SCREENSHOT BLOCK. This exact transaction_id was already submitted at #{original_time}.
            Original status was '#{original_status}'. You MUST NOT confirm this payment or apply any bonus.
            Reply to the customer in Bella's casual lowercase tone: 'looks like you already used this one —
            i got you loaded up from this same screenshot at #{formatted_time}. each screenshot can only be
            used once, send a fresh one if you wanna add more.' Do not deviate from this script.
          INJ
          dup_labels = if duplicate_match_tier == :transaction_id
                         %w[fraud-watch duplicate-attempt]
                       else
                         %w[fraud-watch duplicate-attempt soft-match]
                       end
          add_conversation_labels!(dup_labels)
        end

        unless log_entry['flag_reason']
          bridge_conversation = @bridge_account_id.present? ? Account.find_by(id: @bridge_account_id)&.conversations&.find_by(display_id: @conversation_id) : nil
          expected_platform = bridge_conversation&.additional_attributes&.dig('expected_platform')
          expected_handle = bridge_conversation&.additional_attributes&.dig('expected_handle')

          handle_resolver_confident = resolved.present? &&
            resolved[:score] >= 60 &&
            resolved[:handle].platform.to_s.downcase == payment[:platform].to_s.downcase

          if handle_resolver_confident
            log_entry['resolved_handle'] = resolved[:handle].display_handle
            log_entry['resolve_score'] = resolved[:score]
          elsif expected_platform.present? && payment[:platform].to_s.downcase != expected_platform.to_s.downcase
            ocr_platform = payment[:platform].to_s.downcase
            alt_handle = nil
            if acct && PaymentHandle::PLATFORMS.include?(ocr_platform)
              alt_ph = acct.payment_handles.active_for(ocr_platform).order(:priority).first
              alt_handle = alt_ph&.display_handle
            end

            add_conversation_labels!(%w[wrong-platform])
            log_entry['kind'] = 'flagged'
            log_entry['flag_reason'] = 'wrong_platform'
            log_entry['expected_platform'] = expected_platform
            log_entry['paid_platform'] = ocr_platform

            grok_injection = <<~INJ.squish
              PLATFORM MISMATCH (do not accuse the customer — small mistake, recoverable).
              You gave them the #{expected_platform.upcase} handle "#{expected_handle}" earlier in the chat.
              Their screenshot shows they actually paid via #{ocr_platform.upcase} to "#{payment[:recipient_handle]}" — a stranger with the same handle string on a different app. We did NOT receive that payment.
              Reply in Bella's casual lowercase tone, max 2 lines, no bullets. Apologize warmly (it's an easy mix-up, $ and @ formats look similar across apps). Then offer BOTH options in ONE message:
              Option 1: re-send the same amount on #{expected_platform.upcase} to "#{expected_handle}"
              Option 2: switch to #{ocr_platform.upcase} — #{alt_handle.present? ? %(our #{ocr_platform.upcase} handle is "#{alt_handle}") : %(you'll need to wait while we grab the right #{ocr_platform.upcase} handle)}
              Do NOT confirm a deposit or bonus. Do NOT say "verify you sent it to" — they verified, the issue is the platform itself.
            INJ
            Rails.logger.warn("[ReplyService] WRONG_PLATFORM expected=#{expected_platform} got=#{ocr_platform} contact=#{contact_id}")
          elsif log_entry['flag_reason'].blank?
            platform = payment[:platform].to_s.downcase
            db_norms = if acct && PaymentHandle::PLATFORMS.include?(platform)
                       acct.payment_handles.where(platform: platform).map(&:normalized_handle).uniq.reject(&:blank?)
                     else
                       []
                     end
            legacy = OUR_HANDLES[platform]
            legacy_norms = Array(legacy).map { |h| h.to_s.gsub(/^[\$@]/, '').strip.downcase }.reject(&:blank?)
            expected_norms = db_norms.presence || legacy_norms

            if !handle_resolver_confident && recip_handle.present? && expected_norms.any? && !expected_norms.include?(recip_handle)
              log_entry['kind'] = 'flagged'
              log_entry['flag_reason'] = 'recipient_mismatch'
              expected_display = if db_norms.any? && acct
                                   Payments::HandleSelector.new(acct).pick(platform)&.display_handle
                                 elsif legacy.present?
                                   legacy.first.to_s.start_with?('$') ? legacy.first.to_s : "$#{legacy.first}"
                                 end
              log_entry['expected_handle'] = expected_display
              Rails.logger.warn("[ReplyService] RECIPIENT_MISMATCH expected=#{expected_norms} got=#{recip_handle} contact=#{contact_id}")
              grok_injection = "RECIPIENT MISMATCH. Customer's receipt shows the payment was sent to '#{payment[:recipient_handle]}' on #{platform}, but our handle is #{expected_display}. The payment did NOT come to us. Politely tell them the screenshot shows the payment went to a different account and ask them to verify they sent it to #{expected_display}. Do NOT confirm a deposit and do NOT offer a bonus."
            end
          end
        end

        if grok_injection.blank?
          case extracted_payment_status_bucket(payment[:status])
          when :pending
            if log_entry['kind'] == 'deposit' && log_entry['flag_reason'].blank?
              log_entry['status'] = 'Pending'
            end
          when :failed
            if log_entry['kind'] == 'deposit' && log_entry['flag_reason'].blank?
              log_entry['status'] = 'Failed'
            end
          end
        end

        updated_logs = existing_logs + [log_entry]
        attrs['patra_finance_logs'] = updated_logs
        patch_response = HTTParty.patch(
          "#{base_url}/api/v1/accounts/#{account_id}/contacts/#{contact_id}",
          headers: chatwoot_headers.merge('Content-Type' => 'application/json'),
          body: { custom_attributes: attrs }.to_json,
          timeout: HTTP_TIMEOUT
        )

        st = extracted_payment_status_normalized(payment[:status])
        if patch_response.success? && log_entry['kind'] == 'deposit' && log_entry['flag_reason'].blank? && %w[completed success].include?(st)
          record_payment_handle_success!(acct, payment[:platform].to_s.downcase, recip_handle)
        end

        unless patch_response.success?
          Rails.logger.warn(
            "[ReplyService] patra_finance_logs patch failed HTTP #{patch_response.code}: #{patch_response.body}"
          )
        end
      end
    end

    Rails.logger.info(
      "[ReplyService] auto-logged deposit amount=#{payment[:amount]} platform=#{payment[:platform]} image_only=#{image_only}"
    )

    # Instant IMAP verification — async so Bella replies immediately
    begin
      Payments::SingleContactImapJob.set(wait: 5.seconds).perform_later(contact_id, account_id) if contact_id.present?
      Rails.logger.info("[ReplyService] queued async IMAP check contact=#{contact_id}")
    rescue StandardError => e
      Rails.logger.warn("[ReplyService] IMAP enqueue failed contact=#{contact_id}: #{e.message}")
    end

    return { payment: payment, log_entry: log_entry } if image_only

    {
      payment: payment,
      grok_injection: grok_injection,
      log_entry: log_entry,
      contact_id: contact_id,
      acct: acct,
      recip_handle: recip_handle
    }
  end

  # ---------- Conversation context ----------

  def ai_disabled?
    response = HTTParty.get(
      "#{base_url}/api/v1/accounts/#{account_id}/conversations/#{@conversation_id}",
      headers: chatwoot_headers,
      timeout: HTTP_TIMEOUT
    )

    unless response.success?
      Rails.logger.warn("[AiReply] conversation lookup HTTP #{response.code} conversation=#{@conversation_id}: #{response.body}")
      return false
    end

    labels = Array(response.parsed_response['labels']).map(&:to_s)
    labels.include?(SKIP_LABEL)
  end

  # Normalizes Chatwoot message_type (integer enum, string digits, or legacy string names).
  def chat_message_type(message)
    raw = message['message_type']
    case raw
    when 0, '0', 'incoming' then 0
    when 1, '1', 'outgoing' then 1
    else
      int = raw.to_i
      return int if [0, 1].include?(int)

      nil
    end
  end

  # F16: hold AI replies while a HUMAN agent is actively working the
  # conversation. Window from ENV PATRA_TAKEOVER_PAUSE_MINUTES, read at
  # call-time; default 0 = feature OFF (gate inert, current behavior).
  # The 'ai-off' label flow is a separate gate and stays untouched.
  def human_takeover_pause_active?
    minutes = ENV.fetch('PATRA_TAKEOVER_PAUSE_MINUTES', '0').to_i
    return false if minutes <= 0

    last = @last_human_agent_outgoing_unix.to_i
    return false if last < FRESHNESS_UNIX_MIN

    (Time.current.to_i - last) < (minutes * 60)
  end

  # Unix seconds for sorting / freshness. Handles Integer and ISO8601 strings; avoids
  # `String#to_i` on timestamps (which yields a useless year fragment).
  def message_created_at_unix(raw)
    case raw
    when Integer then raw
    when Numeric then raw.to_i
    when String
      s = raw.strip
      return s.to_i if s.match?(/\A\d{10,}\z/)

      Time.zone.parse(s).to_i
    else
      raw.to_i
    end
  rescue ArgumentError, TypeError
    0
  end

  def build_messages
    response = HTTParty.get(
      "#{base_url}/api/v1/accounts/#{account_id}/conversations/#{@conversation_id}/messages",
      headers: chatwoot_headers,
      query: { after: 0, before: 2_147_483_647 },
      timeout: HTTP_TIMEOUT
    )

    unless response.success?
      Rails.logger.error("[AiReply] message list HTTP #{response.code} conversation=#{@conversation_id}: #{response.body}")
      return []
    end

    payload = Array(response.parsed_response['payload'])
    # Captured for the freshness check in `call`: the REAL latest incoming
    # (customer) message time. Was hardcoded Time.current, which made the
    # staleness gate a permanent no-op. Empty / outgoing-only payloads leave
    # it 0 -> below FRESHNESS_UNIX_MIN -> gate passes -> the existing
    # no-usable-history path handles them exactly as before.
    @latest_timestamp = payload
                        .select { |m| chat_message_type(m) == 0 }
                        .map { |m| message_created_at_unix(m['created_at']) }
                        .max || 0
    # F16: last HUMAN-agent outgoing message (non-private, not the 'ai_auto'
    # source_id ReplyJob stamps on AI-logged replies) for the takeover pause.
    @last_human_agent_outgoing_unix = payload
                                      .select { |m| chat_message_type(m) == 1 && m['private'] != true && m['source_id'].to_s != 'ai_auto' }
                                      .map { |m| message_created_at_unix(m['created_at']) }
                                      .max || 0
    # Chatwoot serializes message_type as an integer: 0 = incoming, 1 = outgoing.
    # 2/3 are activity/template — skip those, they're not part of the conversation.
    raw_slice = payload
                .select { |m| (t = chat_message_type(m)) && [0, 1].include?(t) }
                .reject { |m| reject_empty_message?(m) }
                .sort_by { |m| message_created_at_unix(m['created_at']) }
                .last(HISTORY_LIMIT)

    capture_routing_context_from_raw_slice(raw_slice)
    history = format_conversation_history_from_raw_slice(raw_slice)
    @conversation_history_for_llm = history

    # OpenAI-compatible APIs require the first message to be `user`. Drop any leading
    # assistant turns so the API doesn't 400 with a role-ordering error.
    history.shift while history.any? && history.first['role'] != 'user'
    history
  end

  def reject_empty_message?(m)
    return false if m['content'].to_s.strip.present?

    chat_message_type(m) == 0 && message_has_image_attachments?(m) ? false : true
  end

  def message_has_image_attachments?(m)
    Array(m['attachments']).any? { |a| attachment_image?(a) }
  end

  def attachment_image?(attachment)
    ft = attachment['file_type'] || attachment[:file_type]
    ft.to_s == 'image' || ft.to_s == '0' || ft == 0
  end

  # Accepts whatever ReplyJob hands us (nil, [], or the bridge-flattened list
  # of { 'type' => 'image', 'url' => '...' } hashes — possibly with symbol keys
  # depending on Sidekiq serialization round-trips). Filters out anything
  # without a usable URL so callers can rely on `first&.[](:url)`.
  def normalize_fb_attachments(raw)
    Array(raw).filter_map do |item|
      next unless item.is_a?(Hash)

      h = item.transform_keys(&:to_s)
      url = h['url'].to_s.presence || h.dig('payload', 'url').to_s.presence
      next if url.blank?

      { type: h['type'].to_s, url: url }
    end
  end

  # FB tags screenshots as type=image. Anything with no type still gets
  # treated as an image — better to over-trigger ImagePaymentExtractor (which
  # cheaply returns is_payment:false for non-payment shots) than to silently
  # drop a real payment screenshot because FB labeled it oddly.
  def first_fb_image_url
    match = @attachments.find do |a|
      t = (a[:type] || a['type']).to_s
      t == 'image' || t.empty?
    end
    return nil unless match

    url = match[:url] || match['url']
    payload_url = match.dig(:payload, :url) || match.dig('payload', 'url')
    (url || payload_url).to_s.presence
  end

  def capture_routing_context_from_raw_slice(raw_slice)
    last_incoming = Array(raw_slice).reverse.find { |m| chat_message_type(m) == 0 }
    if last_incoming
      @routing_last_incoming_raw_content = last_incoming['content'].to_s
      imgs = Array(last_incoming['attachments']).select { |a| attachment_image?(a) }
      first = imgs.first
      url = first && (first['data_url'].presence || first['thumb_url'].presence)
      @routing_image_url = url.to_s.presence
      @routing_has_image = imgs.any? && @routing_image_url.present?
    else
      @routing_last_incoming_raw_content = ''
      @routing_image_url = nil
      @routing_has_image = false
    end
  end

  def format_conversation_history_from_raw_slice(raw_slice)
    Array(raw_slice).map do |m|
      t = chat_message_type(m)
      content = m['content'].to_s
      content = '[image]' if content.strip.empty? && message_has_image_attachments?(m)
      { 'role' => t == 0 ? 'user' : 'assistant', 'content' => content }
    end
  end

  def apply_grok_payment_injection(base_messages)
    inj = @grok_payment_injection.to_s.strip
    return base_messages if inj.blank?

    duped = base_messages.map(&:dup)
    idx = duped.rindex { |m| m['role'].to_s == 'user' }
    return base_messages if idx.nil?

    row = duped[idx].dup
    existing = row['content'].to_s
    row['content'] = "#{inj}\n\n#{existing}".strip
    duped[idx] = row
    duped
  end

  def fetch_sender_contact_id
    conv_response = HTTParty.get(
      "#{base_url}/api/v1/accounts/#{account_id}/conversations/#{@conversation_id}",
      headers: chatwoot_headers,
      timeout: HTTP_TIMEOUT
    )
    return nil unless conv_response.success?

    conv_response.parsed_response.dig('meta', 'sender', 'id')
  end

  # Builds a one-line summary about the contact behind this conversation so
  # the model has context (name, game handle, returning-player signal).
  # Pulls from three Chatwoot endpoints; any single failure short-circuits to
  # '' so the prompt simply omits the section rather than blocking the reply.
  def fetch_player_profile
    # 1. Conversation → sender id + name
    conv_response = HTTParty.get(
      "#{base_url}/api/v1/accounts/#{account_id}/conversations/#{@conversation_id}",
      headers: chatwoot_headers,
      timeout: HTTP_TIMEOUT
    )
    return '' unless conv_response.success?

    sender_name = conv_response.parsed_response.dig('meta', 'sender', 'name')
    contact_id = conv_response.parsed_response.dig('meta', 'sender', 'id')
    return '' if contact_id.blank?

    # 2. Contact → additional_attributes (may carry ops-curated notes)
    contact_response = HTTParty.get(
      "#{base_url}/api/v1/accounts/#{account_id}/contacts/#{contact_id}",
      headers: chatwoot_headers,
      timeout: HTTP_TIMEOUT
    )
    return '' unless contact_response.success?

    contact = contact_response.parsed_response['payload'] || contact_response.parsed_response
    name = (sender_name.presence || contact['name']).to_s
    custom_attrs = contact['custom_attributes'].is_a?(Hash) ? contact['custom_attributes'] : {}
    additional_attrs = contact['additional_attributes'].is_a?(Hash) ? contact['additional_attributes'] : {}

    # Use stored game_username if we already have one, otherwise scan recent
    # messages and persist the result for future calls. Drop junk stored earlier.
    raw_stored = custom_attrs['game_username'].presence ||
                 additional_attrs['game_username'].presence
    if raw_stored.present? && self.class.username_value_denied?(raw_stored)
      clear_game_username(contact_id)
      raw_stored = nil
    end
    game_username = raw_stored.presence || store_player_username(contact_id)

    # 3. Past conversations → count = "previous interactions"
    convos_response = HTTParty.get(
      "#{base_url}/api/v1/accounts/#{account_id}/contacts/#{contact_id}/conversations",
      headers: chatwoot_headers,
      timeout: HTTP_TIMEOUT
    )
    conversations_count = convos_response.success? ? Array(convos_response.parsed_response['payload']).length : 0

    parts = []
    if name.present?
      parts << "Contact display name (internal — do not greet or echo unless confirming identity): #{name}"
    end
    parts << "Customer's game username: #{game_username}" if game_username.present?
    parts << "Previous interactions: #{conversations_count}"
    parts.concat(player_vault_lines(custom_attrs))
    parts.concat(player_memory_lines(custom_attrs))
    tone = player_tone_directive(custom_attrs)
    parts << tone if tone.present?
    notes = (additional_attrs['notes'] || custom_attrs['notes']).to_s.strip
    parts << "Notes: #{notes}" if notes.present?
    parts.join("\n")
  rescue StandardError => e
    Rails.logger.warn("[AiReply] player profile fetch error conversation=#{@conversation_id} #{e.class}: #{e.message}")
    ''
  end

  # One line per tracked vault field (contact custom_attributes) for the LLM.
  def player_vault_lines(custom_attrs)
    h = custom_attrs.stringify_keys
    rows = []
    rows << "Preferred platform (last detected): #{h['preferred_platform']}" if h['preferred_platform'].present?
    if h['total_deposits'].present?
      rows << "Total deposits (running sum, USD): #{format('%.2f', h['total_deposits'].to_f)}"
    end
    if h['total_cashouts'].present? && h['total_cashouts'].to_f.positive?
      rows << "Total cashouts (running sum, USD): #{format('%.2f', h['total_cashouts'].to_f)}"
    end
    rows << "Last deposit amount (USD): #{h['last_deposit_amount']}" if h['last_deposit_amount'].present?
    rows << "Last deposit date: #{h['last_deposit_date']}" if h['last_deposit_date'].present?
    rows << "Last cashout date: #{h['last_cashout_date']}" if h['last_cashout_date'].present?
    rows << "Last cashout intent expressed at: #{h['last_cashout_intent_date']}" if h['last_cashout_intent_date'].present?
    rows << "Deposit count: #{h['deposit_count']}" if h['deposit_count'].present?
    if h['preferred_payment_method'].present?
      rows << "Preferred payment method (last detected): #{h['preferred_payment_method']}"
    end
    rows << "Loyalty tier: #{h['loyalty_tier']}" if h['loyalty_tier'].present?
    rows << "First contact date: #{h['first_contact_date']}" if h['first_contact_date'].present?
    if h['preferred_bonus_percentage'].present?
      rows << "Preferred bonus % (last mentioned): #{h['preferred_bonus_percentage']}%"
    end

    raw_logs = Array(h['patra_finance_logs'])
    recent_logs = raw_logs.last(5) # only most recent 5 entries — keeps prompt under Grok's comfort zone
    if recent_logs.any?
      Rails.logger.info(
        "[ReplyService] patra_finance_logs llm_context sent=#{recent_logs.size} stored=#{raw_logs.size} conv=#{@conversation_id}"
      )
      rows << 'Recent finance log entries (last 5; image URLs omitted from prompt):'
      recent_logs.each_with_index do |log, idx|
        next unless log.is_a?(Hash)

        line = finance_log_summary_for_llm(log.stringify_keys, idx + 1)
        rows << line if line.present?
      end
    end

    return [] if rows.empty?

    ['Player profile vault (structured):', *rows]
  end

  # Lines from the player's permanent AI memory (custom_attributes
  # ['patra_player_memory'], distilled by Ai::PlayerMemoryWriter) so Bella
  # replies in a way tailored to who this player is. [] when none distilled yet.
  def player_memory_lines(custom_attrs)
    # Account-level kill switch: skip memory injection when an operator turned
    # it off in AI settings. Defaults to ENABLED on any lookup error so a
    # pref-read failure never silently disables a working feature.
    begin
      pref = ReplyPreference.find_by(account_id: account_id)
      return [] if pref && pref.memory_enabled == false
    rescue StandardError
      nil
    end

    mem = custom_attrs.stringify_keys['patra_player_memory']
    return [] unless mem.is_a?(Hash)

    h = mem.stringify_keys
    rows = []
    summary = h['summary'].to_s.strip
    rows << "Who this player is (from past history): #{summary}" if summary.present?

    traits = h['traits'].is_a?(Hash) ? h['traits'].stringify_keys : {}
    trait_bits = %w[style patience attitude].filter_map do |k|
      "#{k}: #{traits[k].to_s.strip}" if traits[k].to_s.strip.present?
    end
    rows << "Player traits — #{trait_bits.join(', ')}" if trait_bits.any?

    rows
  end

  # Short directive so Bella adjusts warmth without naming the customer.
  def player_tone_directive(custom_attrs)
    h = custom_attrs.stringify_keys
    tier = h['loyalty_tier'].to_s.downcase
    count = h['deposit_count'].to_i
    total = format('%.2f', h['total_deposits'].to_f)

    case tier
    when 'vip'
      "RELATIONSHIP TONE: VIP player (#{count} deposits, ~$#{total} lifetime loads). Be extra warm and appreciative; " \
      'they are a core regular — never sound transactional or cold.'
    when 'loyal'
      "RELATIONSHIP TONE: Loyal player (#{count} deposits). Sound like you know them already — friendly, no hand-holding."
    when 'regular'
      "RELATIONSHIP TONE: Regular player (#{count} deposits). Normal buddy energy, still concise."
    when 'casual'
      'RELATIONSHIP TONE: Casual player (a few deposits). Welcoming but keep replies short.'
    when 'new'
      'RELATIONSHIP TONE: New or nearly new player (0–1 deposits). Friendly hello energy; do not push hard on bonuses.'
    else
      ''
    end
  end

  # Values that must never be persisted as game_username (greetings, acks,
  # business keywords mistaken for handles, etc.). Checked case-insensitively.
  USERNAME_VALUE_DENYLIST = %w[
    test testing hi hello hey heyy heyyy yes no ok okay sure thanks thank thx ty yo wassup sup
    yeah nah lol lmao please help what how why when where who
    admin root user guest player account login password
    load cashout deposit scam scammer wtf fraud fire good bad
  ].freeze

  # Persists game_username only when:
  # 1) Customer writes an explicit line ("username: X", "my username is X",
  #    "my game username is X", or a clear correction like "my real username is X"), or
  # 2) Customer sends a single plausible handle token and the nearest prior
  #    assistant turn asked for their game username (see ASSISTANT_USERNAME_PROMPT_REGEX).
  # Chatwoot merges custom_attributes on update; removals use destroy_custom_attributes.
  # Returns the detected username on success, nil on no-match or any failure.
  USERNAME_EXPLICIT_PATTERN = /
    (?:
      my\s+(?:game\s+)?username\s+is|
      my\s+(?:game\s+)?username\s*:|
      (?:^|[\s>])(?:game\s+)?username\s*:
    )
    \s*
    ([^\s.,;:!?]+)
  /ix
  USERNAME_CORRECTION_PATTERN = /
    (?:
      my\s+real\s+(?:game\s+)?username\s+is|
      actually\s+(?:my\s+)?(?:real\s+)?(?:game\s+)?username\s+is|
      (?:wrong|sorry)[,:\s]+(?:my\s+)?(?:real\s+)?(?:game\s+)?username\s+is|
      correct(?:ion)?[,:\s]+(?:my\s+)?(?:real\s+)?(?:game\s+)?username\s+is
    )
    \s*
    ([^\s.,;:!?]+)
  /ix
  USERNAME_SCAN_LIMIT = 20
  # Bella asked for their in-game handle (matches phrasing in SYSTEM_PROMPT / ops style).
  ASSISTANT_USERNAME_PROMPT_REGEX = /
    what(?:'s|s|\s+is)\s+your\s+[\w\s]{0,24}username
    |\byour\s+\w+\s+username\b
    |\busername\s*\?
    |,\s*username\s*\?
  /ix

  def store_player_username(contact_id)
    return nil if contact_id.blank?

    messages_response = HTTParty.get(
      "#{base_url}/api/v1/accounts/#{account_id}/conversations/#{@conversation_id}/messages",
      headers: chatwoot_headers,
      timeout: HTTP_TIMEOUT
    )
    return nil unless messages_response.success?

    timeline = username_scan_timeline(messages_response.parsed_response['payload'])
    action = detect_username_action_from_timeline(timeline)
    return nil if action.nil?

    case action[:type]
    when :clear
      clear_game_username(contact_id)
      nil
    when :set
      persist_game_username(contact_id, action[:value])
    end
  rescue StandardError => e
    Rails.logger.warn("[AiReply] store_player_username error contact=#{contact_id} #{e.class}: #{e.message}")
    nil
  end

  def username_scan_timeline(payload)
    Array(payload)
      .select { |m| (t = chat_message_type(m)) && [0, 1].include?(t) }
      .reject { |m| m['content'].to_s.strip.empty? }
      .sort_by { |m| message_created_at_unix(m['created_at']) }
      .last(USERNAME_SCAN_LIMIT * 2)
  end

  # Newest customer messages first; first actionable row wins (latest customer intent).
  def detect_username_action_from_timeline(timeline)
    incoming_indices = timeline.each_with_index.filter_map { |m, i| i if chat_message_type(m) == 0 }
    incoming_indices.reverse_each do |idx|
      message = timeline[idx]
      content = message['content'].to_s.strip
      next if content.empty?

      if (m = content.match(USERNAME_CORRECTION_PATTERN))
        token = normalize_username_capture(m[1])
        next if token.blank?

        return { type: :clear } if self.class.username_value_denied?(token)

        return { type: :set, value: token }
      end

      if (m = content.match(USERNAME_EXPLICIT_PATTERN))
        token = normalize_username_capture(m[1])
        next if token.blank?
        next if self.class.username_value_denied?(token)

        return { type: :set, value: token }
      end

      next unless single_word_username_reply?(content)

      assistant = prior_assistant_message(timeline, idx)
      next if assistant.blank?
      next unless assistant_prompted_game_username?(assistant['content'].to_s)

      token = normalize_username_capture(content.sub(/\A[@#]/, '').sub(/[.,;:!?]+\z/, ''))
      next if token.blank?
      next if self.class.username_value_denied?(token)

      return { type: :set, value: token }
    end
    nil
  end

  def single_word_username_reply?(content)
    normalized = content.gsub(/\s+/, ' ').strip
    return false if normalized.include?(' ')

    token = normalize_username_capture(normalized.sub(/\A[@#]/, '').sub(/[.,;:!?]+\z/, ''))
    token.present? && token.match?(/\A[a-zA-Z0-9][a-zA-Z0-9_.-]{0,48}\z/)
  end

  def prior_assistant_message(timeline, incoming_index)
    return nil if incoming_index < 1

    (incoming_index - 1).downto(0) do |j|
      return timeline[j] if chat_message_type(timeline[j]) == 1
    end
    nil
  end

  def assistant_prompted_game_username?(text)
    text.match?(ASSISTANT_USERNAME_PROMPT_REGEX)
  end

  def normalize_username_capture(raw)
    raw.to_s.strip.sub(/\A[@#]+/, '').sub(/[.,;:!?]+\z/, '')
  end

  def persist_game_username(contact_id, username)
    patch_response = HTTParty.patch(
      "#{base_url}/api/v1/accounts/#{account_id}/contacts/#{contact_id}",
      headers: chatwoot_headers.merge('Content-Type' => 'application/json'),
      body: { custom_attributes: { game_username: username } }.to_json,
      timeout: HTTP_TIMEOUT
    )

    if patch_response.success?
      Rails.logger.info("[AiReply] stored game_username=#{username} contact=#{contact_id}")
      username
    else
      Rails.logger.warn("[AiReply] failed to persist game_username HTTP #{patch_response.code}: #{patch_response.body}")
      nil
    end
  end

  def clear_game_username(contact_id)
    return if contact_id.blank?

    response = HTTParty.post(
      "#{base_url}/api/v1/accounts/#{account_id}/contacts/#{contact_id}/destroy_custom_attributes",
      headers: chatwoot_headers.merge('Content-Type' => 'application/json'),
      body: { custom_attributes: ['game_username'] }.to_json,
      timeout: HTTP_TIMEOUT
    )

    if response.success?
      Rails.logger.info("[AiReply] cleared game_username contact=#{contact_id}")
    else
      Rails.logger.warn("[AiReply] clear game_username HTTP #{response.code}: #{response.body}")
    end
  end

  # Fetches every canned response in the account and formats them as
  # `short_code: content` blocks separated by blank lines. Cached in Redis the
  # same way the per-code fetches are. Used to inject the full reference into
  # the prompt so the model can cite ops-managed answers verbatim.
  def fetch_all_canned_responses
    cached = read_canned_cache('__all__')
    return cached if cached.present?

    response = HTTParty.get(
      "#{base_url}/api/v1/accounts/#{account_id}/canned_responses",
      headers: chatwoot_headers,
      timeout: HTTP_TIMEOUT
    )

    unless response.success?
      Rails.logger.warn("[AiReply] all canned-responses lookup HTTP #{response.code}: #{response.body}")
      return ''
    end

    entries = Array(response.parsed_response).filter_map do |c|
      short_code = c['short_code'].to_s.strip
      content = c['content'].to_s.strip
      next nil if short_code.empty? || content.empty?

      "#{short_code}: #{content}"
    end
    return '' if entries.empty?

    formatted = entries.join("\n\n")
    write_canned_cache('__all__', formatted)
    formatted
  rescue StandardError => e
    Rails.logger.warn("[AiReply] all canned-responses fetch error #{e.class}: #{e.message}")
    ''
  end

  # Best-effort Redis read/write for canned-response content. Any Redis error
  # (connection refused, $redis undefined in dev/test, etc.) is swallowed so
  # the caller falls through to the HTTP path.
  def read_canned_cache(short_code)
    $redis.get("#{CANNED_CACHE_PREFIX}#{short_code}")
  rescue StandardError
    nil
  end

  def write_canned_cache(short_code, content)
    $redis.setex("#{CANNED_CACHE_PREFIX}#{short_code}", CANNED_CACHE_TTL, content)
  rescue StandardError
    nil
  end

  # Pulls the current payment-method tags/links from a Chatwoot canned response
  # so the prompt always reflects what ops has configured today (without a
  # deploy). Falls back to '' on any failure — the prompt template tells the
  # model to escalate when payment details are missing or blank.
  def fetch_payment_info
    cached = read_canned_cache('payment_info')
    return cached if cached.present?

    response = HTTParty.get(
      "#{base_url}/api/v1/accounts/#{account_id}/canned_responses",
      headers: chatwoot_headers,
      query: { search: 'payment_info' },
      timeout: HTTP_TIMEOUT
    )

    unless response.success?
      Rails.logger.warn("[AiReply] payment_info lookup HTTP #{response.code}: #{response.body}")
      return ''
    end

    match = Array(response.parsed_response).find { |c| c['short_code'].to_s == 'payment_info' }

    if match.nil?
      fallback = payment_info_from_handles
      if fallback.present?
        Rails.logger.info("[AiReply] payment_info canned response missing account=#{account_id} - using live payment-handle fallback")
        write_canned_cache('payment_info', fallback)
        return fallback
      end
      Rails.logger.warn("[AiReply] payment_info canned response not found in account=#{account_id} and no active payment handles")
      return ''
    end

    content = match['content'].to_s
    write_canned_cache('payment_info', content)
    content
  rescue StandardError => e
    Rails.logger.warn("[AiReply] payment_info fetch error #{e.class}: #{e.message}")
    ''
  end

  # When ops has not created the payment_info canned response, build the
  # payment block from the LIVE active payment handles via
  # Bella::PaymentInfoBuilder (single best handle per platform: active, not
  # in cooldown, lowest failure_count then priority) and inject it as EXACT
  # REQUIRED OUTPUT so the model copies handles character-for-character.
  # Empty when no usable handles -> caller keeps the '' escalation path.
  # Cached under the same canned key (TTL 600s) so a later canned response
  # takes over within 10 minutes.
  def payment_info_from_handles
    account = Account.find_by(id: account_id)
    line = defined?(Bella::PaymentInfoBuilder) ? Bella::PaymentInfoBuilder.for(account: account) : nil
    return '' if line.to_s.strip.empty?

    <<~TEXT.strip
      EXACT REQUIRED OUTPUT - ACTIVE PAYMENT HANDLES:
      #{line}
      Any payment handle in your reply MUST be copied character-for-character from the line above.
      If the customer asked about one specific platform, give ONLY that platform's handle - never the full list.
    TEXT
  rescue StandardError => e
    Rails.logger.warn("[AiReply] payment_info handle fallback failed #{e.class}: #{e.message}")
    ''
  end

  # Pulls a persona definition (short_code: ai_persona) so ops can rename and
  # re-voice the agent without a deploy. Empty / missing → no identity section
  # is prepended to the prompt.
  def fetch_ai_persona
    cached = read_canned_cache('ai_persona')
    return cached if cached.present?

    response = HTTParty.get(
      "#{base_url}/api/v1/accounts/#{account_id}/canned_responses",
      headers: chatwoot_headers,
      query: { search: 'ai_persona' },
      timeout: HTTP_TIMEOUT
    )

    unless response.success?
      Rails.logger.warn("[AiReply] ai_persona lookup HTTP #{response.code}: #{response.body}")
      return ''
    end

    match = Array(response.parsed_response).find { |c| c['short_code'].to_s == 'ai_persona' }

    if match.nil?
      Rails.logger.info("[AiReply] ai_persona canned response not found in account=#{account_id}")
      return ''
    end

    content = match['content'].to_s
    write_canned_cache('ai_persona', content)
    content
  rescue StandardError => e
    Rails.logger.warn("[AiReply] ai_persona fetch error #{e.class}: #{e.message}")
    ''
  end

  # Pulls a free-form "ops training notes" canned response (short_code:
  # ai_training) so the team can refine model behavior from the Chatwoot UI
  # without redeploying. Empty / missing → no extra section added.
  def fetch_ai_training
    cached = read_canned_cache('ai_training')
    return cached if cached.present?

    response = HTTParty.get(
      "#{base_url}/api/v1/accounts/#{account_id}/canned_responses",
      headers: chatwoot_headers,
      query: { search: 'ai_training' },
      timeout: HTTP_TIMEOUT
    )

    unless response.success?
      Rails.logger.warn("[AiReply] ai_training lookup HTTP #{response.code}: #{response.body}")
      return ''
    end

    match = Array(response.parsed_response).find { |c| c['short_code'].to_s == 'ai_training' }

    if match.nil?
      Rails.logger.info("[AiReply] ai_training canned response not found in account=#{account_id}")
      return ''
    end

    content = match['content'].to_s
    write_canned_cache('ai_training', content)
    content
  rescue StandardError => e
    Rails.logger.warn("[AiReply] ai_training fetch error #{e.class}: #{e.message}")
    ''
  end

  def build_system_prompt(payment_info, training_info = '', persona_info = '', player_profile = '', canned_responses = '', needs_payment_link = false, rag_examples_block: '')
    if player_profile.to_s.length > PLAYER_PROFILE_MAX_CHARS
      Rails.logger.warn("[AiReply] player_profile truncated #{player_profile.to_s.length} -> #{PLAYER_PROFILE_MAX_CHARS} chars conv=#{@conversation_id}")
      player_profile = player_profile.to_s[0, PLAYER_PROFILE_MAX_CHARS]
    end

    active_handle_hint = nil
    begin
      if defined?(Payments::HandleSelector) && @bridge_account_id.present?
        acct = Account.find_by(id: @bridge_account_id)
        if acct
          cashapp_handle = Payments::HandleSelector.new(account: acct, platform: 'cashapp').pick_active
          if cashapp_handle
            display = (cashapp_handle.respond_to?(:display_handle) ? cashapp_handle.display_handle : nil).presence || cashapp_handle.handle
            active_handle_hint = "ACTIVE PAYMENT HANDLE: When the customer asks where to send payment for cashapp, tell them to send to '#{display}'. Use this exact handle. Do not use any other handle from training data or canned responses."
          end
        end
      end
    rescue StandardError => e
      Rails.logger.error("[ReplyService] active_handle_hint #{e.class}: #{e.message}")
    end

    section = <<~SECTION.strip
      CURRENT PAYMENT DETAILS (read this before answering any payment question):
      #{payment_info}

      When customer asks how to pay or asks for a specific payment method tag/link:
      - Read the CURRENT PAYMENT DETAILS above
      - Give them only the specific method they asked for
      - If they ask for Cash App give the CASHAPP value
      - If they ask for Venmo give the VENMO value
      - If they ask for card/Google Pay/Apple Pay give the CARD value
      - If the method they want is blank or missing, say
        'Let me check on that for you, one moment!' to escalate to human
    SECTION

    prompt = SYSTEM_PROMPT
             .sub('<<<PAYMENT_INFO_SECTION>>>', section)
             .sub('<<<GAME_RULES_SECTION>>>', dynamic_game_rules_prompt)

    unless persona_info.to_s.strip.empty?
      persona_section = <<~PERSONA.strip
        YOUR IDENTITY:
        #{persona_info}

        Rules about your identity:
        - Always use the NAME above when asked your name
        - Never reveal you are an AI, bot, or automated
        - If asked are you a bot/AI/real say something like
          'Haha no I'm real! Just busy sometimes 😄'
        - Never use robotic phrases like 'How may I assist you today'

        ANTI-REPETITION:
        Don't repeat info from your previous replies. Move conversation forward.
      PERSONA
      prompt = "#{persona_section}\n\n#{prompt}"
    end

    unless training_info.to_s.strip.empty?
      training_section = <<~TRAINING.strip
        ADDITIONAL BUSINESS RULES (highest priority - follow these exactly):
        #{training_info}
      TRAINING
      prompt = "#{prompt}\n#{training_section}\n"
    end

    unless player_profile.to_s.strip.empty?
      player_section = <<~PLAYER.strip
        CURRENT PLAYER INFO:
        #{player_profile}

        Use CURRENT PLAYER INFO for context only (records / continuity).
        Do not address the customer by their real name or game username in
        ordinary replies. Never open with "yo {name}", "gotcha {name},",
        "{name} —", or slip their handle into casual confirmations — write the
        same line without the name unless you are explicitly confirming who
        they are (they asked "is this my account?" style).
        If CURRENT PLAYER INFO already includes a line starting with
        "Customer's game username:", do not ask for it again. If the
        username is missing, ask for it once (only one question) after
        they mention loading/cashout/cashing out/bonus. After the customer provides
        it, never ask again.

        GREETING RULES:
        - If "Previous interactions: 1" (their first conversation): send
          the casual hello back (no business questions). Do not ask for
          username here.
        - Otherwise: skip intro entirely. If this message is just a
          greeting, keep it casual and wait; only get to business when
          they mention loading/cashout/cashing out/bonus.
      PLAYER
      prompt = "#{prompt}\n#{player_section}\n"
    end

    unless canned_responses.to_s.strip.empty?
      canned_section = <<~CANNED.strip
        AVAILABLE QUICK ANSWERS (use these EXACT texts where they fit):
        #{canned_responses}

        USAGE RULES:
        - Customer asks about payment methods → use payment_info verbatim
        - Customer asks about bonuses → reference ai_training rules
        - Never make up info that already exists in a canned response
      CANNED
      prompt = "#{prompt}\n#{canned_section}\n"
    end

    payment_link_section = <<~PAYRULES.strip
      PAYMENT LINK RULE:
      - Card / Apple Pay / Google Pay / Visa / Mastercard → ALWAYS send the
        BoltPay link from CURRENT PAYMENT DETAILS above
      - Cash App → give the CASHAPP tag from payment_info
      - Venmo → give the VENMO tag
      - Chime → give the CHIME tag
      - PayPal → give the PAYPAL email
      - Never ask "which method?" if the customer already named one
    PAYRULES
    prompt = "#{prompt}\n#{payment_link_section}\n"

    if needs_payment_link
      prompt = "#{prompt}\nIMMEDIATE INSTRUCTION: The customer just mentioned a card or pay-link option. You MUST include the BoltPay/CARD link from CURRENT PAYMENT DETAILS in this reply — do not ask them which method.\n"
    end

    base_prompt = "#{prompt.strip}\n\n#{payment_handles_context_for_prompt}\n"
    result = active_handle_hint.present? ? "#{active_handle_hint}\n\n#{base_prompt}" : base_prompt
    result = "#{result}\n\n#{rag_examples_block}" unless rag_examples_block.to_s.strip.empty?
    result
  end

  # ---------- Grok (xAI) + DeepSeek ----------

  def invoke_anthropic(messages, system_prompt, use_deepseek: false)
    if @rag_examples.present? || @reply_pref.present?
      system_prompt = build_rag_enhanced_prompt(system_prompt, @rag_examples || [], @reply_pref)
    end

    llm_messages = use_deepseek ? messages.map { |m| { role: m['role'].to_s == 'assistant' ? 'assistant' : 'user', content: m['content'].to_s } } : messages

    Rails.logger.info("[ReplyService] GROK_HTTP_TIMEOUT=#{GROK_HTTP_TIMEOUT}s xAI conv=#{@conversation_id}") unless use_deepseek

    # BATCH C: Grok/xAI retired (credits exhausted). DeepSeek is the only live brain.
    # The grok ternary branches below are dead (no caller passes use_deepseek:false)
    # but kept intact so XAI_URL/MODEL/api_key constants stay referenced.
    llm_url = use_deepseek ? 'https://api.deepseek.com/v1/chat/completions' : XAI_URL
    llm_headers = {
      'Authorization' => "Bearer #{use_deepseek ? ENV['DEEPSEEK_API_KEY'] : api_key}",
      'Content-Type' => 'application/json'
    }
    Rails.logger.info("[AiReply] prompt_chars=#{system_prompt.to_s.length} history_msgs=#{llm_messages.size} conv=#{@conversation_id}")
    # THINKING-DISABLED reply path (research fix, June 2026): DeepSeek v4-flash
    # defaults thinking ON, so on multi-step asks it burns 5-7k chars of
    # reasoning_content and hits finish_reason=length BEFORE writing the reply
    # (ReplyGuard then rejects -> retry -> holding line: the #1 fail cluster).
    # We disable thinking for Bella's customer reply ONLY, hard-cap tokens, and
    # stop at a blank line so even a bad call ends clean at <=2 lines. Top-level
    # `thinking:{type:disabled}` is the documented DeepSeek param (api-docs
    # thinking_mode); recognized params don't error. ENV kill-switch
    # DEEPSEEK_DISABLE_THINKING=false reverts to reasoning with no redeploy.
    disable_thinking = use_deepseek && ENV.fetch('DEEPSEEK_DISABLE_THINKING', 'true') != 'false'
    deepseek_opts = if !use_deepseek
                      {}
                    elsif disable_thinking
                      { temperature: 0.7, stop: ["\n\n"], thinking: { type: 'disabled' } }
                    else
                      { temperature: 0.7 } # kill-switch reverted: byte-exact original body
                    end
    # Thinking off => the model writes only the 2-line answer, so a small cap is
    # SAFE (no reasoning to starve); clamped so a stale high env can't ramble.
    # Thinking ON (kill-switch reverted) keeps the old generous headroom so the
    # flag is a CLEAN revert, not a worse-than-before starve.
    reply_max = if !use_deepseek
                  MAX_TOKENS
                elsif disable_thinking
                  [ENV.fetch('DEEPSEEK_MAX_TOKENS', 200).to_i, 512].min
                else
                  ENV.fetch('DEEPSEEK_MAX_TOKENS', 1600).to_i
                end
    llm_body_h = {
      model: use_deepseek ? ENV.fetch('DEEPSEEK_MODEL', 'deepseek-v4-flash') : MODEL,
      max_tokens: reply_max,
      messages: [{ role: 'system', content: system_prompt }, *llm_messages],
      **deepseek_opts
    }
    llm_body = llm_body_h.to_json
    # Phase 2: the regen must NOT replay identical params. With thinking off,
    # tighten to one short line at half the tokens. When reverted to thinking,
    # fall back to the original same-body regen (reasoning needs its headroom).
    retry_body = if use_deepseek && disable_thinking
                   llm_body_h.merge(
                     max_tokens: 100,
                     messages: [{ role: 'system',
                                  content: "#{system_prompt}\n\nReply with ONE short line — the answer only, no reasoning, no preamble." },
                                *llm_messages]
                   ).to_json
                 else
                   llm_body
                 end
    llm_timeout = use_deepseek ? ENV.fetch('DEEPSEEK_HTTP_TIMEOUT', 30).to_i : GROK_HTTP_TIMEOUT
    provider = use_deepseek ? 'DeepSeek' : 'xAI'

    response = nil
    attempt = 0
    begin
      attempt += 1
      response = HTTParty.post(llm_url, headers: llm_headers, body: llm_body, timeout: llm_timeout)
    rescue Net::OpenTimeout, Net::ReadTimeout, Errno::ECONNRESET, EOFError, SocketError => e
      if attempt < 2
        Rails.logger.warn("[AiReply] #{provider} network #{e.class} attempt #{attempt}, retrying conv=#{@conversation_id}")
        retry
      end
      Rails.logger.error("[AiReply] #{provider} network error conv=#{@conversation_id}: #{e.class}: #{e.message}")
      return nil
    end

    # Retry once on 5xx ONLY (never on 4xx — auth/quota won't fix on retry).
    if !response.success? && response.code.to_i >= 500 && attempt < 2
      Rails.logger.warn("[AiReply] #{provider} HTTP #{response.code} attempt #{attempt}, retrying conv=#{@conversation_id}")
      attempt += 1
      response = begin
        HTTParty.post(llm_url, headers: llm_headers, body: llm_body, timeout: llm_timeout)
      rescue Net::OpenTimeout, Net::ReadTimeout, Errno::ECONNRESET, EOFError, SocketError => e
        Rails.logger.error("[AiReply] #{provider} retry network error conv=#{@conversation_id}: #{e.class}: #{e.message}")
        nil
      end
      return nil if response.nil?
    end

    unless response.success?
      Rails.logger.error("[AiReply] #{provider} HTTP #{response.code} conversation=#{@conversation_id}: #{response.body}")
      return nil
    end

    # DeepSeek flash returns the ANSWER in content and chain-of-thought in
    # reasoning_content — content FIRST, reasoning only when content is empty
    # (prevents leaking the CoT/persona rules to the customer).
    msg = response.parsed_response.dig('choices', 0, 'message') || {}
    text = msg['content'].to_s.strip
    text = msg['reasoning_content'].to_s.strip if text.blank?
    if text.blank?
      Rails.logger.warn("[AiReply] #{provider} returned no text conversation=#{@conversation_id} body=#{response.body}")
      return nil
    end

    # ReplyGuard - reasoning/over-length shipped as the reply never reaches the
    # player. Regen on an invalid reply OR a finish_reason=length truncation,
    # using the TIGHTENED retry_body (Phase 2) instead of identical params.
    finish = begin
      response.parsed_response.dig('choices', 0, 'finish_reason')
    rescue StandardError
      nil
    end
    guard_ok = self.class.reply_guard_valid?(text)
    if !guard_ok || finish == 'length'
      Rails.logger.warn("[ReplyGuard] regen conv=#{@conversation_id} guard_ok=#{guard_ok} finish=#{finish} chars=#{text.length} head=#{text[0, 200].inspect}")
      retry_text = reply_guard_retry(llm_url, llm_headers, retry_body, llm_timeout)
      if retry_text
        text = retry_text
      elsif !guard_ok
        # original was invalid AND the tightened regen failed -> holding line.
        # Log as a MEASURED DEGRADATION so the fallback rate stays countable.
        Rails.logger.warn("[ReplyGuard] MEASURED_DEGRADATION fallback shipped conv=#{@conversation_id} finish=#{finish}")
        reply_guard_escalate(text)
        return REPLY_GUARD_FALLBACK
      end
      # else: original was guard-VALID (only finish=length) and regen failed ->
      # keep the valid original rather than degrade to the holding line.
    end

    Rails.logger.info("[ReplyService] RAG-enhanced reply. Examples: #{@rag_examples&.length || 0}, tone: #{@reply_pref&.reply_tone || 'default'}")

    text
  end

  # ReplyGuard - ONE same-prompt regeneration after an invalid reply. Returns
  # valid text or nil (network/HTTP/empty/still-invalid all -> nil). Same
  # content-first -> reasoning_content parse order as the main call.
  def reply_guard_retry(llm_url, llm_headers, llm_body, llm_timeout)
    response = HTTParty.post(llm_url, headers: llm_headers, body: llm_body, timeout: llm_timeout)
    return nil unless response.success?

    msg = response.parsed_response.dig('choices', 0, 'message') || {}
    text = msg['content'].to_s.strip
    text = msg['reasoning_content'].to_s.strip if text.blank?
    return text if text.present? && self.class.reply_guard_valid?(text)

    Rails.logger.warn("[ReplyGuard] retry also invalid conv=#{@conversation_id} chars=#{text.length} head=#{text[0, 200].inspect}")
    nil
  rescue StandardError => e
    Rails.logger.warn("[ReplyGuard] retry generation failed conv=#{@conversation_id}: #{e.class}: #{e.message}")
    nil
  end

  # ReplyGuard - both generations were reasoning/garbage: the player gets
  # REPLY_GUARD_FALLBACK; the group gets the full 5-part picture.
  def reply_guard_escalate(bad_text)
    esc_account = Account.find_by(id: account_id)
    return unless esc_account && defined?(Games::TelegramNotifier)

    esc_contact_id = begin
      fetch_sender_contact_id
    rescue StandardError
      nil
    end
    esc_contact = esc_contact_id ? esc_account.contacts.find_by(id: esc_contact_id) : nil
    esc_conv = @conversation_id ? esc_account.conversations.find_by(display_id: @conversation_id) : nil
    player_msg = @routing_last_incoming_raw_content.to_s.strip[0..160]
    Games::TelegramNotifier.human_escalation(
      account: esc_account,
      contact: esc_contact,
      reason: "PLAYER WANTS: #{player_msg.empty? ? 'see conversation' : player_msg} | " \
              'ALREADY DONE: 2 bad generations BLOCKED by ReplyGuard (model reasoning leaked as the reply); player got a holding line | ' \
              'STILL LEFT: the real answer | ' \
              'BELLA SUGGESTS: reply by hand from the dashboard | ' \
              "NEEDS FROM HUMAN: answer the player. Bad output head: #{bad_text.to_s.strip[0, 180].inspect}",
      conversation: esc_conv
    )
  rescue StandardError => e
    Rails.logger.error("[ReplyGuard] escalation failed conv=#{@conversation_id}: #{e.class}: #{e.message}")
  end

  # ---------- Escalation ----------

  def escalation?(reply)
    downcased = reply.to_s.downcase
    ESCALATION_PHRASES.any? { |phrase| downcased.include?(phrase) }
  end

  # Returns :escalate / :level_2 / :level_1 / nil based on the latest user
  # message. :escalate only when they explicitly demand a human/manager;
  # :level_1 / :level_2 keep Bella in the loop with tailored tone hints.
  def detect_anger_level(messages)
    user_msgs = messages.select { |m| m['role'] == 'user' }
    return nil if user_msgs.empty?

    latest = user_msgs.last['content'].to_s.downcase

    return :escalate if explicit_human_request?(latest)

    return :level_2 if matches_any_keyword?(latest, ANGER_LEVEL_2_KEYWORDS)
    return :level_1 if matches_any_keyword?(latest, ANGER_LEVEL_1_KEYWORDS)

    nil
  end

  def explicit_human_request?(text)
    down = text.to_s.downcase
    EXPLICIT_HUMAN_REQUEST_PHRASES.any? { |phrase| down.include?(phrase) }
  end

  # Word-boundary match for single words, substring match for phrases. Stops
  # "report" tripping on "reports" while still catching "fix this now".
  def matches_any_keyword?(text, keywords)
    keywords.any? do |kw|
      if kw.include?(' ')
        text.include?(kw)
      else
        text.match?(/\b#{Regexp.escape(kw)}\b/)
      end
    end
  end

  # Empathy directives injected after the regular system prompt. Kept terse
  # so they don't blow up token spend on a frustrated customer reply.
  def empathy_hint_for(level)
    case level
    when :level_2
      'CUSTOMER IS ANGRY OR UPSET (e.g. scam/fraud accusations, strong language). Do NOT say let me check on that / one moment / manager handoff. ' \
      'Do NOT offer a manager or human unless they explicitly asked for one. Apologize briefly, own the confusion, then ask for their game username ' \
      'so you can help (even if they have not mentioned load yet — you need the handle to look into it). ' \
      'Tone example (do not copy verbatim): hey im really sorry this feels off, whats your game username so i can sort this? Stay casual; no corporate speak.'
    when :level_1
      'CUSTOMER SHOWS MILD FRUSTRATION OR IMPATIENCE (wait time, where is my load, etc.). Acknowledge it with empathy and reassure you are on it — no handoff. ' \
      'Tone example (do not copy verbatim): i totally get it, lemme check rn 🙏 Keep it short and human; one emoji max only if it fits.'
    end
  end

  # Posts the AI escalation private note and adds needs-human (not ai-off) so
  # a teammate can take over. Only used when the customer explicitly asked for
  # a human/manager — never for anger keywords alone.
  def escalate_to_human(messages, matched_keyword)
    Rails.logger.info("[AiReply] escalating explicit-handoff conversation=#{@conversation_id} match=#{matched_keyword}")

    last_user_message = messages.reverse.find { |m| m['role'] == 'user' }&.dig('content').to_s.strip
    note = "🤖 AI escalation: Customer needs human attention - #{last_user_message}"

    HTTParty.post(
      "#{base_url}/api/v1/accounts/#{account_id}/conversations/#{@conversation_id}/messages",
      headers: chatwoot_headers.merge('Content-Type' => 'application/json'),
      body: { content: note, message_type: 'outgoing', private: true }.to_json,
      timeout: HTTP_TIMEOUT
    )

    HTTParty.post(
      "#{base_url}/api/v1/accounts/#{account_id}/bulk_actions",
      headers: chatwoot_headers.merge('Content-Type' => 'application/json'),
      body: { type: 'Conversation', ids: [@conversation_id], labels: { add: %w[needs-human] } }.to_json,
      timeout: HTTP_TIMEOUT
    )
  rescue StandardError => e
    Rails.logger.error("[AiReply] escalate_to_human failed conversation=#{@conversation_id} #{e.class}: #{e.message}")
  end

  # Best-effort label add for payment-screenshot follow-up (bulk_actions).
  def add_conversation_labels!(labels)
    list = Array(labels).map(&:to_s).reject(&:blank?)
    return if list.empty?

    HTTParty.post(
      "#{base_url}/api/v1/accounts/#{account_id}/bulk_actions",
      headers: chatwoot_headers.merge('Content-Type' => 'application/json'),
      body: { type: 'Conversation', ids: [@conversation_id], labels: { add: list } }.to_json,
      timeout: HTTP_TIMEOUT
    )
  rescue StandardError => e
    Rails.logger.error("[AiReply] add_conversation_labels failed conversation=#{@conversation_id} #{e.class}: #{e.message}")
  end

  # bp5 P1: chokepoint guard for FALSE COMPLETED-ACTION CLAIMS (all 5 reply
  # exits route through here). A reply may assert a completed/in-progress
  # money action ONLY when a matching real GameAction succeeded in the last
  # 5 minutes; otherwise the claim is rewritten to intent-form and the
  # deterministic path acts/escalates. Families: load (original behavior,
  # reply + label unchanged), transfer/switch ("Transferred to panda masters
  # ✅", "switching to fire kirin now"), payout ("Got it, paying now"). Also
  # kills % bonus promises that trace to no configured rule ("40% is still
  # on for you"). Phrasing about the CUSTOMER's inbound payment ("lmk when
  # you sent it") and R3's blessed "sending that request now" stay untouched.
  def guard_against_false_load_claim(reply_text)
    reply_text = enforce_exact_payment_handles(reply_text)
    reply_text = strip_handle_person_names(reply_text)
    return reply_text if reply_text.blank?

    reply_text = guard_against_unconfigured_bonus_claim(reply_text)
    return reply_text if reply_text.blank?

    # it6 (A1c): block bonus/referral/cashout FREELANCING — haggling/negotiation
    # ("best i can do", "can't go above"), promise-to-add ("throw in", "add it next
    # time"), money-context promise-fix. Engages only on money-flavored replies.
    reply_text = guard_against_policy_freelancing(reply_text)
    return reply_text if reply_text.blank?

    # it6 (A4): block INVENTED on-account balances — a $ balance not traceable to the
    # customer's own last message defers to a check line.
    reply_text = guard_against_invented_balance(reply_text)
    return reply_text if reply_text.blank?

    # bp5 P8 (red-team A): fold common Cyrillic/Greek homoglyphs to Latin
    # BEFORE matching so "lоаded" can't smuggle a false claim past the
    # word-boundary patterns. Match on the folded copy; the customer-visible
    # text is never mutated.
    scan_text = fold_homoglyphs(reply_text)

    # completed/credited-by-synonym LOAD claims. PAST-TENSE / done-state only;
    # in-progress phrasings ("processing", "verifying", "sending that request
    # now") and the credential-delivery "all set! username..." are deliberately
    # NOT here so they pass untouched.
    load_claim_patterns = [
      /\bloaded\b/i,
      /\bloading\b/i,
      /got it.{0,20}load/i,
      /lemme load/i,
      /let me load/i,
      /loading you up/i,
      /you'?re? (set|good|loaded|topped\s*up|all\s*good)/i,
      /done.{0,10}load/i,
      /✅/,
      /\b(?:added|credited|deposited)\b[^.!?\n]{0,30}\b(?:to|in|into|on|onto|your)\b/i,
      /\b(?:funds?|money|credits?|balance|points?)\b[^.!?\n]{0,20}\b(?:added|credited|deposited|loaded|in\s+there|topped\s*up)\b/i,
      /\btopped\s+(?:you|u|it|your\s+account)\s*(?:up|off)?\b/i,
      /\bput\s+(?:it|you|that|the\s+(?:funds|money|load))\s+on\b/i,
      /\b(?:your\s+)?(?:money|funds?|cash|credits?)(?:'s|\s+is|\s+are)?\s+in\b/i,
      /\bit'?s\s+in\s+there\b/i,
      /\bin\s+there\s+now\b/i,
      /\bbalance\b[^.!?\n]{0,20}\b(?:updated|reflects?|reflected|good\s+to\s+go)\b/i,
      /\bknocked\b[^.!?\n]{0,20}\b(?:load|out)\b/i,
      /\ball\s+set\s+on\b/i
    ]
    transfer_claim_patterns = [
      /\btransferr?ed\b/i,
      /\bswitch(?:ed|ing)\b[^.!?\n]{0,30}\b(?:now|over)\b/i,
      # bp GroupD-FC: PAST-TENSE completed switch "switched to juwa". Gerund
      # "switching to X for you" is an OFFER, not a completion -> excluded.
      /\bswitched\b[^.!?\n]{0,30}\b(?:to|onto)\b/i,
      /\bmoved\s+(?:it|you|your|that|everything)\b/i
    ]
    payout_claim_patterns = [
      /\b(?:i|we)(?:'ve)?\s+(?:just\s+)?(?:sent|paid)\b/i,
      /\bpaying\s+(?:you\s+|it\s+|that\s+)?(?:now|rn)\b/i,
      /\bgot\s+it[,!.]?\s*paying\b/i,
      /\b(?:sent|paid)\s+(?:your|the|it|that)\b[^.!?\n]{0,24}\b(?:cash\s*out|cashout|payout|winnings|request|way|out)\b/i,
      /\bsent\s+it\s+(?:your\s+way|out|over)\b/i,
      /\b(?:cash\s*out|cashout|payout|winnings)\b[^.!?\n]{0,20}\b(?:sent|paid|done|completed|processed|went\s+out)\b/i,
      /\b(?:payout|cashout|cash\s*out)\b[^.!?\n]{0,12}\bprocessed\b/i,
      /\bpaid\s+out\s+(?:your|the|it)\b/i,
      /\bwent\s+out\s+(?:a\s+min|already|just\s+now)\b/i,
      # bp GroupD-FC: "sending your cashout now" — in-progress payout claim. GERUND
      # "sending" only (NOT bare "send", so "send me your cashout tag" stays free),
      # gated on a cashout/payout keyword so blessed "sending that request now"
      # (no such keyword) stays untouched.
      /\bsending\b[^.!?\n]{0,20}\b(?:cash\s*out|cashout|payout|winnings)\b/i,
      # bp: bare past-tense "paid" as Bella's OWN completion claim — no checkmark,
      # no cashout keyword, no i/we subject (e.g. "Sure Paid hun", "Paid", "ok
      # paid now"). Either the reply OPENS with paid (after light filler) OR it's
      # paid + endearment/now/already. Customer-direction "you paid" / "once
      # you've paid" / "get paid?" don't open with paid and aren't paid+<list>,
      # so they pass. A TRUE payout still clears via the recent-cashout evidence
      # gate below; only an unbacked claim is rewritten to the defer line.
      /\A\s*(?:sure|ok|okay|yes|yep|yeah|aight|alright|right|done|got\s*it|lmc|k|np|all\s+good)?[\s,!.]*paid\b/i,
      /\bpaid\s+(?:hun|love|babe|boo|fam|bro|sis|dear|now|already)\b/i
    ]

    claim_kind =
      if payout_claim_patterns.any? { |p| scan_text.match?(p) }
        :payout
      elsif transfer_claim_patterns.any? { |p| scan_text.match?(p) }
        :transfer
      elsif load_claim_patterns.any? { |p| scan_text.match?(p) }
        :load
      end
    return reply_text unless claim_kind

    cid = fetch_sender_contact_id
    return reply_text if cid.blank?

    recent_success = GameAction
                     .where(contact_id: cid, status: 'success')
                     .where('game_actions.created_at > ?', 5.minutes.ago)
    evidence =
      case claim_kind
      when :load then recent_success.where(action_type: 'load').exists?
      when :payout then recent_success.where(action_type: 'cashout').exists?
      when :transfer
        # a real game-to-game transfer = redeem (cashout) + recharge (load)
        recent_success.where(action_type: 'cashout').exists? &&
          recent_success.where(action_type: 'load').exists?
      end

    return reply_text if evidence

    Rails.logger.warn("[ReplyService] BLOCKED_FALSE_#{claim_kind.to_s.upcase}_CLAIM contact=#{cid} reply=#{reply_text.inspect[0..120]}")
    if claim_kind == :load
      add_conversation_labels!(%w[blocked-false-load-claim]) rescue nil
      'verifying your payment with the bank, takes 1-5 min — hang tight 🙏'
    else
      add_conversation_labels!(%w[blocked-false-action-claim]) rescue nil
      'on it — getting that going for you now, one sec 🙏'
    end
  end

  # bp5 P8 (red-team A): map the common Cyrillic/Greek homoglyphs that
  # visually impersonate Latin a-z so a claim word spelled with lookalike
  # letters still trips the guard. Lowercase mapping is enough (patterns are /i).
  HOMOGLYPH_FOLD = {
    'а' => 'a', 'е' => 'e', 'о' => 'o', 'с' => 'c', 'р' => 'p', 'х' => 'x',
    'у' => 'y', 'к' => 'k', 'м' => 'm', 'н' => 'h', 'т' => 't', 'в' => 'b',
    'і' => 'i', 'ј' => 'j', 'ѕ' => 's', 'ԁ' => 'd', 'ɡ' => 'g',
    'α' => 'a', 'ο' => 'o', 'ρ' => 'p', 'ε' => 'e', 'ι' => 'i', 'ν' => 'v',
    'ѵ' => 'v', 'ⅼ' => 'l', 'ո' => 'n'
  }.freeze

  def fold_homoglyphs(text)
    text.to_s.chars.map { |ch| HOMOGLYPH_FOLD[ch.downcase] || ch }.join
  rescue StandardError
    text.to_s
  end

  # it6 (A1c v3) — fold homoglyphs AND fullwidth digits/percent to ASCII before guard matching so
  # "４５％" and Cyrillic lookalikes can't evade. Customer-visible text is never mutated.
  def normalize_guard_text(text)
    fold_homoglyphs(text).tr('０-９', '0-9').tr('％', '%')
  rescue StandardError
    text.to_s
  end

  # bp5 P1: a % bonus PROMISE must trace to a configured percentage (an
  # enabled GameRule deposit_bonus_percentage, or the player's stored
  # bonus_percent_override / preferred_bonus_percentage). Plain percents with
  # no promise wording pass through. Fails open on any error.
  BONUS_PROMISE_CONTEXT = /\b(?:bonus|match(?:ing)?|promo|extra|still\s+on|on\s+for\s+you|you\s+get|you'?ll\s+(?:get|see)|rate|pays?\s+out|comes?\s+(?:out\s+)?to|up\s+to|referral|between\s+us|call\s+it|we(?:'?re|\s+are)\s+at|i\s+got\s+(?:you|ya|u)\s+at|i'?ll\s+(?:give|add|throw|do|make|stretch)|i\s+can\s+(?:give|do|stretch)|stretch\s+it)\b/i

  def guard_against_unconfigured_bonus_claim(reply_text)
    return reply_text if reply_text.to_s.strip.empty?

    scan = normalize_guard_text(reply_text)
    percents = scan.scan(/(\d{1,3}(?:\.\d{1,2})?)\s*(?:%|percent\b)/i).flatten
    return reply_text if percents.empty?
    return reply_text unless scan.match?(BONUS_PROMISE_CONTEXT)

    allowed = configured_bonus_percents
    stray = percents.reject { |p| allowed.include?(p.to_f) }
    return reply_text if stray.empty?

    Rails.logger.warn("[ReplyService] BLOCKED_UNCONFIGURED_BONUS_CLAIM stray=#{stray.join(',')} reply=#{reply_text.inspect[0..120]}")
    add_conversation_labels!(%w[blocked-false-action-claim]) rescue nil
    'lemme double check what bonus is running for you rn — one sec 🙏'
  rescue StandardError => e
    Rails.logger.warn("[ReplyService] bonus claim guard failed: #{e.class}: #{e.message}")
    reply_text
  end

  # it6 (A1c) — memoized agent-policy resolver for this reply's account (nil-safe, memoizes nil).
  def policy_resolver
    return @policy_resolver if defined?(@policy_resolver)

    acct = Account.find_by(id: account_id)
    @policy_resolver = acct ? Games::PolicyResolver.new(account: acct, now: Time.current) : nil
  rescue StandardError => e
    Rails.logger.warn("[ReplyService] policy_resolver init failed: #{e.class}: #{e.message}")
    @policy_resolver = nil
  end

  # it6 (A1c) — Bella must NEVER negotiate or freelance bonus/referral/cashout terms. These
  # phrasings are off-limits regardless of configured policy. Engage ONLY on a money-flavored
  # reply so non-money support replies ("i'll fix the login link") pass untouched. Fails open.
  # match/double promises with no number — always off-limits (Bella never offers these).
  POLICY_ALWAYS_BLOCK = Regexp.union(
    /\bdouble\s+(?:your|the)\s+(?:deposit|load|money)\b/i,
    /\bmatch\s+(?:it|your\s+(?:deposit|load))\b/i,
    /\bdollar\s+for\s+dollar\b/i
  )
  # haggling/negotiating a number — blocked whenever the reply carries a number ($/%/digit);
  # no money-word required (haggle phrasing IS a terms statement). "best i can do is escalate"
  # (no number) passes.
  POLICY_NEGOTIATION_PATTERNS = Regexp.union(
    /\bbest i can do\b/i,
    /\bcan'?t go (?:any\s+)?(?:higher|above|over|past)\b/i,
    /\bcan'?t do (?:any\s+)?(?:less|lower|more)\b/i,
    /\bjust this once\b/i,
    /\b(?:i'?ll|i can|i will|lemme|let me)\s+do\s+\$?\d/i,
    /\b(?:give|giving|get)\s+(?:you|ya|u)\s+\$?\d/i,
    /\bmake\s+it\s+\$?\d/i,
    /\b(?:i'?ll|i can|i could)\s+stretch\b/i,
    /\bmax i can (?:give|do|go)\b/i,
    /\bfor\s+you[, ]+\$?\d/i,
    /\bsince you asked\b/i,
    /\bbump\s+(?:it|that|you|your\s+\w+)\s+(?:up|to)\b/i,
    /\b(?:we'?ll\s+)?call it\s+\$?\d/i,
    /\bi\s+got\s+(?:you|ya|u)\s+at\s+\$?\d/i,
    /\bround\s+(?:it\s+)?(?:up\s+|down\s+)?to\s+\$?\d/i,
    /\bbetween\s+us[,: ]+\$?\d/i,
    /\b\d+\s*:\s*\d+\b/
  )
  # promise to ADD value — blocked when money-flavored AND a money object follows the verb
  # (so "throw in the screenshot" / "add the extra info to your ticket" pass). The fix/sort
  # branch is narrowed to a BONUS object so "i'll fix your cashout" is NOT touched.
  POLICY_ADD_PATTERNS = Regexp.union(
    /\b(?:throw|threw|toss|tossed|throwing|tossing)\s+in\s+(?:you\s+|ya\s+|u\s+)?(?:an?\s+|some\s+|another\s+|the\s+)?(?:extra|bonus|comp|\$?\d|\d+\s*%)/i,
    /\b(?:i'?ll|i will|lemme|let me|i can|i could)\s+(?:add|tack\s+on|throw\s+on)\s+(?:in\s+)?(?:you\s+|ya\s+|u\s+)?(?:an?\s+|some\s+|another\s+)?(?:extra|bonus|comp|\$?\d|\d+\s*%)/i,
    /\badd\s+(?:that\s+|the\s+)?(?:extra\s+)?bonus\s+(?:next\s+time|later|on\s+next)\b/i,
    /\b(?:i'?ll|i will)\s+sweeten\b/i,
    /\bon the house\b/i,
    /\bhook\s+(?:you|ya|u)\s+up\s+(?:with\s+)?(?:a\s+|an\s+|some\s+)?(?:bonus|extra|comp|\$?\d|\d+\s*%)/i,
    /\bbump\s+(?:your\s+)?(?:bonus|comp)\b/i,
    /\bi(?:'?ll| will)\s+(?:fix|sort|take\s+care\s+of)\b[^.!?\n]{0,24}\bbonus\b/i,
    /\b(?:here'?s|heres|got\s+(?:you|ya|u))\s+(?:a\s+)?\$?\d+\s*(?:comp|bonus)\b/i,
    /\bget\s+(?:you|ya|u)\s+\$?\d+\s*(?:extra|comp|bonus|credit)\b/i,
    /\$\d+\s*comp\b/i
  )
  MONEY_FLAVOR = %r{[$%]|\b(?:bonus|match|promo|cash\s*out|cashout|referral|credit|extra|comp(?:ed)?|bucks?|dollars?)\b}i

  def guard_against_policy_freelancing(reply_text)
    return reply_text if reply_text.to_s.strip.empty?

    # match on a homoglyph-folded copy (customer text unchanged) so lookalike letters can't
    # smuggle a freelance phrase past the patterns.
    scan = normalize_guard_text(reply_text)
    has_number = scan.match?(/[$%]|\b\d/)
    blocked = scan.match?(POLICY_ALWAYS_BLOCK) ||
              (has_number && scan.match?(POLICY_NEGOTIATION_PATTERNS)) ||
              (scan.match?(MONEY_FLAVOR) && scan.match?(POLICY_ADD_PATTERNS))
    return reply_text unless blocked

    Rails.logger.warn("[ReplyService] BLOCKED_POLICY_FREELANCE reply=#{reply_text.inspect[0..120]}")
    add_conversation_labels!(%w[blocked-false-action-claim]) rescue nil
    'lemme confirm what we got going for you right now — one sec 🙏'
  rescue StandardError => e
    Rails.logger.warn("[ReplyService] policy freelance guard failed: #{e.class}: #{e.message}")
    reply_text
  end

  # it6 (A4) — Bella must never state a SPECIFIC on-account balance she wasn't given. A $ balance
  # figure that doesn't trace to the customer's own last message (or simple pairwise sums of those
  # numbers) is rewritten to a defer/check line. Deposit/load confirmations, cashout limits, and the
  # customer echoing their own number are NOT balance claims. Fails open.
  BALANCE_FIGURE = /
    (?:^|[\s$])(\d{1,6}(?:\.\d{1,2})?)\s+(?:left|remaining|in\s+there)\b
    | (?:^|[\s$])(\d{1,6}(?:\.\d{1,2})?)\s+(?:on\s+(?:your\s+)?account|in\s+your\s+account)\b
    | \bbalance\s+(?:is\s+|of\s+|:\s*|=\s*)?\$?(\d{1,6}(?:\.\d{1,2})?)\b
    | (?:sitting\s+at|you'?re\s+at)\s+\$(\d{1,6}(?:\.\d{1,2})?)\b
  /ix

  def guard_against_invented_balance(reply_text)
    return reply_text if reply_text.to_s.strip.empty?

    claimed = normalize_guard_text(reply_text).scan(BALANCE_FIGURE).flatten.compact.map(&:to_f)
    return reply_text if claimed.empty?

    allowed = customer_provided_numbers
    stray = claimed.reject { |c| allowed.any? { |a| (a - c).abs < 0.01 } }
    return reply_text if stray.empty?

    Rails.logger.warn("[ReplyService] BLOCKED_INVENTED_BALANCE stray=#{stray.join(',')} reply=#{reply_text.inspect[0..120]}")
    add_conversation_labels!(%w[blocked-false-action-claim]) rescue nil
    'lemme pull up your balance real quick so i get it right — one sec 🙏'
  rescue StandardError => e
    Rails.logger.warn("[ReplyService] balance guard failed: #{e.class}: #{e.message}")
    reply_text
  end

  # Numbers the customer themselves provided in their last message (+ simple pairwise sums) — the only
  # figures Bella may state back as a balance. [] when unavailable (=> any stated balance defers).
  def customer_provided_numbers
    txt = @routing_last_incoming_raw_content.to_s
    nums = txt.scan(/\d{1,6}(?:\.\d{1,2})?/).map(&:to_f).uniq
    sums = []
    nums.combination(2).each { |a, b| sums << (a + b).round(2) } if nums.size <= 8
    (nums + sums).uniq
  rescue StandardError
    []
  end

  # Percent values Bella is allowed to promise: enabled GameRule bonuses for
  # this account + the player's stored bonus attrs. [] on any error (=> every
  # percent promise gets the safe check line).
  def configured_bonus_percents
    # it6 (A1c): when the owner defined agent_policy bonuses, that is authoritative —
    # only ACTIVE-window bonus percents may be stated; GameRule is NOT consulted. [] here
    # => no bonus active right now => the % guard defers every promise.
    resolver = policy_resolver
    allowed =
      if resolver&.bonuses_configured?
        resolver.active_bonus_percents.dup
      else
        legacy = []
        GameRule.where(account_id: account_id).each do |r|
          next unless r.respond_to?(:deposit_bonus_enabled) && r.deposit_bonus_enabled

          legacy << r.deposit_bonus_percentage.to_f if r.deposit_bonus_percentage.present?
        end
        cid = begin
          fetch_sender_contact_id
        rescue StandardError
          nil
        end
        contact = cid.present? ? Contact.find_by(id: cid, account_id: account_id) : nil
        if contact
          ca = (contact.custom_attributes || {}).stringify_keys
          %w[bonus_percent_override preferred_bonus_percentage].each do |k|
            v = ca[k].to_s[/\d+(?:\.\d+)?/]
            legacy << v.to_f if v
          end
        end
        legacy
      end
    allowed << resolver.referral['percent'].to_f if resolver&.referral_configured? && resolver.referral['percent']
    allowed
  rescue StandardError => e
    Rails.logger.warn("[ReplyService] configured_bonus_percents failed: #{e.class}: #{e.message}")
    []
  end

  # Payfix output guard: any $/@ tag in the reply that is NOT an exact active
  # payment handle but normalizes to one (case/whitespace removed) is
  # rewritten to the exact handle from payment_handles. Tags matching no
  # active handle are customer-owned (e.g. their own cashout tag) and are
  # never touched. Fails open: any error returns the reply unchanged.
  def enforce_exact_payment_handles(reply_text)
    return reply_text if reply_text.to_s.strip.empty?

    acct = Account.find_by(id: account_id)
    return reply_text unless acct.respond_to?(:payment_handles)

    exact_by_norm = {}
    acct.payment_handles.to_a.each do |h|
      next unless h.status.to_s == 'active'

      norm = h.normalized_handle.to_s.gsub(/\s+/, '')
      next if norm.empty?

      exact_by_norm[norm] ||= h.display_handle.to_s
    end
    return reply_text if exact_by_norm.empty?

    reply_text.gsub(/[\$@][A-Za-z0-9][A-Za-z0-9 ._\-]{0,40}/) do |tag|
      rewrite_tag_to_exact_handle(tag, exact_by_norm)
    end
  rescue StandardError => e
    Rails.logger.warn("[ReplyService] enforce_exact_payment_handles failed: #{e.class}: #{e.message}")
    reply_text
  end

  # Longest prefix of the greedy tag match (trimming trailing space-separated
  # chunks) whose case/whitespace-stripped form equals an active handle wins;
  # the trimmed remainder is re-appended untouched. No match -> tag unchanged.
  def rewrite_tag_to_exact_handle(tag, exact_by_norm)
    candidate = tag.to_s
    remainder = ''
    loop do
      norm = candidate.sub(/\A[\$@]/, '').gsub(/\s+/, '').downcase
      exact = exact_by_norm[norm]
      return "#{exact}#{remainder}" if !norm.empty? && exact

      break unless candidate.include?(' ')

      head, _sep, tail = candidate.rpartition(' ')
      remainder = " #{tail}#{remainder}"
      candidate = head
    end
    tag
  end

  def extracted_payment_status_normalized(raw)
    s = raw.to_s.downcase.strip
    return 'unknown' if s.blank?

    # Map all failure variants to canonical 'failed'
    failure_words = %w[failed cancel canceled cancelled declined rejected denied refused returned blocked reversed bounced void voided unsuccessful]
    return 'failed' if failure_words.any? { |w| s.include?(w) }

    # Map all success variants to canonical 'completed'
    success_words = %w[completed complete success successful approved confirmed paid received delivered settled]
    return 'completed' if success_words.any? { |w| s.include?(w) }

    # Map all pending variants to canonical 'pending'
    pending_words = %w[pending processing waiting awaiting sent submitted hold review verifying]
    return 'pending' if pending_words.any? { |w| s.include?(w) }

    s
  end

  # Maps ImagePaymentExtractor `status` (and legacy values) to a coarse bucket
  # for screenshot replies. Fraud flags (duplicate / recipient mismatch) are
  # handled earlier via `grok_injection` — this runs only when that is nil.
  def extracted_payment_status_bucket(raw)
    case extracted_payment_status_normalized(raw)
    when 'completed', 'success'
      :confirmed
    when 'pending', 'sent'
      :pending
    when 'failed'
      :failed
    else
      :unknown
    end
  end

  # Sidebar-friendly vault status (from `extracted_payment_status_bucket`).
  def finance_log_status_label(bucket)
    case bucket
    when :confirmed then 'Screenshot Received'
    when :pending then 'Screenshot Received'
    when :failed then 'Failed'
    else 'Unknown'
    end
  end

  # Compact one-line per finance log row for Grok system prompt (no image URLs).
  def finance_log_summary_for_llm(e, index)
    parts = [
      e['kind'].presence,
      e['amount'].present? ? "$#{e['amount']}" : nil,
      e['platform'].presence,
      (e['status'].presence || e['raw_status'].presence),
      e['transaction_id'].present? ? "tx=#{e['transaction_id']}" : nil,
      e['flag_reason'].presence ? "flag=#{e['flag_reason']}" : nil
    ].compact
    return nil if parts.empty?

    "  #{index}. #{parts.join(' | ')}"
  end

  # Composite key for duplicate screenshot detection when `transaction_id` is blank (e.g. Cash App pending).
  def payment_screenshot_fingerprint_composite(data)
    amount = (data[:amount] || data['amount']).to_s.strip
    sender = (data[:sender_handle] || data['sender_handle']).to_s.strip.downcase
    recipient = (data[:recipient_handle] || data['recipient_handle']).to_s.strip.downcase
    tx_time = (data[:transaction_time] || data['transaction_time']).to_s.strip
    tx_date = (data[:transaction_date] || data['transaction_date']).to_s.strip
    tx_id = (data[:transaction_id] || data['transaction_id']).to_s.strip
    platform = (data[:platform] || data['platform']).to_s.strip.downcase
    sender_name = (data[:sender_name] || data['sender_name']).to_s.strip.downcase
    recipient_name = (data[:recipient_name] || data['recipient_name']).to_s.strip.downcase

    # Count how many strong identifying fields are populated
    strong_fields = [sender, recipient, tx_time, tx_date, tx_id, sender_name, recipient_name].count { |f| f.present? }

    # If fewer than 3 strong fields are populated, the fingerprint isn't reliable enough.
    # Return nil to disable soft duplicate matching for this screenshot (the strict transaction_id
    # tier still runs separately and catches real duplicates).
    return nil if strong_fields < 3

    [amount, sender, recipient, tx_time, tx_date, sender_name, recipient_name, platform].join('|')
  end

  # True if the latest user message mentions a card / pay-link keyword.
  # Drives the "you MUST send the BoltPay link" directive in the prompt.
  def needs_payment_link?(messages)
    last_user = messages.reverse.find { |m| m['role'] == 'user' }
    return false unless last_user

    text = last_user['content'].to_s.downcase
    PAYMENT_LINK_KEYWORDS.any? { |kw| text.include?(kw) }
  end

  # True when the latest user text looks like a payment failure AND recent
  # turns mention a handle, amount, or payment routing intent (last 6 msgs).
  def text_payment_failure_signal?(messages)
    return false if messages.blank?

    last_user = messages.reverse.find { |m| (m[:role] || m['role']).to_s == 'user' }
    return false unless last_user

    last_text = (last_user[:content] || last_user['content']).to_s.downcase
    return false if last_text.blank?

    strong_signals = [
      /\bit\s+failed\b/, /\bpayment\s+failed\b/, /\btransaction\s+failed\b/, /\bsend\s+failed\b/,
      /\bstill\s+failed\b/, /\bagain\s+failed\b/, /\bjust\s+failed\b/, /\balso\s+failed\b/,
      /\bfailed\s+again\b/, /\bfailed\s+too\b/, /\bfailed\s+this\s+time\b/,
      /\bdidn'?t\s+work\b/, /\bdoesn'?t\s+work\b/, /\bnot\s+working\b/, /\bwon'?t\s+work\b/,
      /\bstill\s+not\s+working\b/, /\bnot\s+working\s+either\b/,
      /\bdeclined\b/, /\brejected\b/, /\bbounced\b/, /\bblocked\b/, /\bcanceled\b/, /\bcancelled\b/,
      /\bcouldn'?t\s+send\b/, /\bcan'?t\s+send\b/, /\bunable\s+to\s+send\b/,
      /\bnot\s+going\s+through\b/, /\bdidn'?t\s+go\s+through\b/, /\bwon'?t\s+go\s+through\b/,
      /\bno\s+luck\b/, /\bstill\s+no\s+luck\b/,
      /\balready\s+said\b/, /\bi\s+said\b/, /\bi\s+told\s+you\b/,
      /\balready\s+told\s+you\b/, /\bjust\s+told\s+you\b/, /\bi\s+just\s+said\b/,
      /\byeah\s+failed\b/, /\bya\s+failed\b/, /\byep\s+failed\b/, /\byup\s+failed\b/,
      /\bnope\s+failed\b/, /\bno\s+failed\b/,
      /\bdidn'?t\s+work\s+either\b/, /\bdidn'?t\s+work\s+again\b/, /\bdidn'?t\s+work\s+too\b/,
      /\bdidn'?t\s+either\b/,
      /\bthat\s+one\s+(failed|didn'?t|too)\b/, /\bthis\s+one\s+(failed|didn'?t|too)\b/,
      /\bthat\s+one\s+also\b/, /\bthat\s+too\s+failed\b/, /\bthat\s+too\s+didn'?t\b/,
      /\bno\s+it\s+didn'?t\b/, /\bno\s+it\s+won'?t\b/, /\bnah\s+failed\b/,
      /\bmoney\s+didn'?t\b/, /\bcash\s+didn'?t\b/, /\bpayment\s+(didn'?t|stuck|hung)\b/,
      /\bgot\s+(rejected|declined|denied|cancelled|canceled)\b/,
      /\bthey\s+(rejected|declined|denied|cancelled|canceled)\b/,
      /\bcard\s+(declined|rejected|denied|failed)\b/,
      /\btried\s+again\b/, /\bsame\s+(issue|problem|thing|error)\b/,
      /\bnot\s+going\s+(in|through|out)\b/, /\bcan'?t\s+pay\b/,
      /\bsend\s+me\s+another\b/, /\bgive\s+me\s+another\b/, /\bneed\s+another\s+(one|tag|handle)\b/,
      /\banother\s+(tag|handle|one|cashapp)\b/, /\bdifferent\s+(tag|handle|one|cashapp)\b/
    ]

    weak_signals = [/\berror\b/, /\bwrong\b/, /\bissue\b/, /\bproblem\b/]

    has_strong = strong_signals.any? { |re| last_text.match?(re) }
    has_weak = weak_signals.any? { |re| last_text.match?(re) }
    return false unless has_strong || has_weak

    recent_messages = messages.last(6)
    context_text = recent_messages.map { |m| (m[:content] || m['content']).to_s.downcase }.join(' ')

    has_handle_mention = context_text.match?(/\$[a-z0-9]+/i) || context_text.match?(/send\s+(to|it)\s+to/)
    has_amount = context_text.match?(/\$\d+/) || context_text.match?(/\b\d+\s+(dollars?|bucks?)\b/)
    has_payment_intent = context_text.match?(/where\s+(do|to)\s+i?\s*send/) || context_text.match?(/where\s+to\s+pay/)

    has_payment_context = has_handle_mention || has_amount || has_payment_intent

    (has_strong && has_payment_context) || (has_weak && has_payment_context)
  rescue StandardError => e
    Rails.logger.warn("[ReplyService] text_payment_failure_signal? crashed: #{e.class}: #{e.message}")
    false
  end

  # E1 hard guard: a customer-facing reply must never contain a configured
  # payment handle's display_name (a PERSON name, e.g. the cashapp account
  # owner) — swap any occurrence for that handle's $/@ tag. Names shorter
  # than 5 chars are skipped (too generic to safely substring-match).
  # Fails open: any error returns the reply unchanged.
  def strip_handle_person_names(reply_text)
    return reply_text if reply_text.to_s.strip.empty?

    acct = Account.find_by(id: account_id)
    return reply_text unless acct.respond_to?(:payment_handles)

    out = reply_text
    acct.payment_handles.to_a.each do |h|
      name = h.try(:display_name).to_s.strip
      next if name.length < 5

      tag = h.respond_to?(:display_handle) ? h.display_handle.to_s : ''
      next if tag.empty?

      # bp5 P8 (red-team B2): a display_name stored with irregular internal
      # whitespace ("dev  patel") must still match single-spaced reply text.
      name_re = name.split(/\s+/).map { |tok| Regexp.escape(tok) }.join('\\s+')
      pattern = /(?<![\$@\w])#{name_re}\b/i
      out = out.gsub(pattern, tag) if out.match?(pattern)
    end
    out
  rescue StandardError => e
    Rails.logger.warn("[ReplyService] strip_handle_person_names failed: #{e.class}: #{e.message}")
    reply_text
  end

  # Cash App text failover: offer backup handle or escalate. Returns reply
  # text or nil (nil → caller continues with normal Bella / LLM flow).
  def maybe_reply_for_text_payment_failure(messages)
    return nil if @grok_payment_injection.present?
    return nil unless defined?(Payments::HandleSelector) && @bridge_account_id.present?
    return nil unless text_payment_failure_signal?(messages)

    acct = Account.find_by(id: @bridge_account_id)
    return nil unless acct

    recent_bella_text = messages.last(6)
                           .select { |m| (m[:role] || m['role']).to_s == 'assistant' }
                           .map { |m| (m[:content] || m['content']).to_s }
                           .join(' ')

    failed_handle = nil
    begin
      acct.payment_handles.where(platform: 'cashapp').each do |ph|
        display = ph.display_name.to_s.downcase
        normalized = ph.normalized_handle.to_s.downcase
        next if display.blank? && normalized.blank?

        down = recent_bella_text.downcase
        if display.present? && down.include?(display)
          failed_handle = ph
          break
        end
        if normalized.present? && down.include?(normalized)
          failed_handle = ph
          break
        end
      end
    rescue StandardError => e
      Rails.logger.warn("[ReplyService] text failover handle scan crashed: #{e.class}: #{e.message}")
      return nil
    end

    return nil unless failed_handle

    backup = begin
      Payments::HandleSelector.new(account: acct, platform: 'cashapp').pick_backup(failed_handle)
    rescue StandardError => e
      Rails.logger.warn("[ReplyService] HandleSelector.pick_backup crashed: #{e.class}: #{e.message}")
      nil
    end

    if backup
      if defined?(Payments::FailoverManager)
        begin
          Payments::FailoverManager.new(failed_handle).record_failure!
        rescue StandardError => e
          Rails.logger.warn("[ReplyService] FailoverManager crashed: #{e.class}: #{e.message}")
        end
      end

      add_conversation_labels!(%w[payment-failed-retry text-detected])

      # E1: customer-facing text carries the $/@ TAG, never the handle's person name.
      backup_display = (backup.respond_to?(:display_handle) ? backup.display_handle : nil).presence || backup.handle
      failed_tag = (failed_handle.respond_to?(:display_handle) ? failed_handle.display_handle : nil).presence || failed_handle.handle

      # E2: a player-reported handle failure + rotation must never be silent.
      # Alert failure must never block the customer reply.
      if defined?(Games::TelegramNotifier)
        begin
          Games::TelegramNotifier.human_escalation(
            account: acct,
            contact: Contact.find_by(id: fetch_sender_contact_id, account_id: acct.id),
            reason: "⚠️ PAYMENT HANDLE FAILED (player-reported): #{failed_tag} → rotated to #{backup_display}"
          )
        rescue StandardError => e
          Rails.logger.warn("[ReplyService] handle-failed telegram alert crashed: #{e.class}: #{e.message}")
        end
      end

      reply = "ah no worries — try sending it to #{backup_display} instead, that one's working"
      Rails.logger.info("[ReplyService] Text failover: #{failed_tag} → #{backup_display}")
      strip_handle_person_names(reply)
    else
      add_conversation_labels!(%w[payment-system-down needs-human])

      if defined?(Payments::EscalationNotifier)
        begin
          Payments::EscalationNotifier.new(acct).notify_all_handles_dead('cashapp')
        rescue StandardError => e
          Rails.logger.warn("[ReplyService] EscalationNotifier crashed: #{e.class}: #{e.message}")
        end
      end

      "having some issues on our end with payments right now, one sec — a manager will jump in to sort this out for you"
    end
  rescue StandardError => e
    Rails.logger.warn("[ReplyService] maybe_reply_for_text_payment_failure crashed: #{e.class}: #{e.message}")
    nil
  end

  # ---------- Helpers / config ----------

  def log_and_nil(message)
    Rails.logger.warn("[AiReply] #{message}")
    nil
  end

  def chatwoot_headers
    { 'api_access_token' => chatwoot_token, 'Accept' => 'application/json' }
  end

  def chatwoot_token
    ENV.fetch('CHATWOOT_BRIDGE_API_TOKEN', '').to_s
  end

  def api_key
    ENV.fetch('XAI_API_KEY', '').to_s
  end

  def base_url
    @base_url ||= ENV.fetch('CHATWOOT_BRIDGE_BASE_URL', 'http://chatwoot.railway.internal:3000').to_s.chomp('/')
  end

  def account_id
    @account_id ||= begin
      aid = @bridge_account_id
      aid = aid.to_i if aid.present?
      if aid.present? && aid.positive?
        aid
      else
        ENV.fetch('CHATWOOT_BRIDGE_ACCOUNT_ID', '2').to_i
      end
    end
  end

  def bella_system_prompt_with_payment_handles
    "#{self.class::SYSTEM_PROMPT}\n\n#{payment_handles_context_for_prompt}"
  end

  def payment_handles_context_for_prompt
    account = Account.find_by(id: account_id)
    unless account
      return no_payment_handles_prompt_text
    end

    selector = Payments::HandleSelector.new(account)
    usable = selector.usable_platforms
    primary = {}
    Array(usable).each do |plat|
      h = selector.pick(plat)
      primary[plat] = h&.display_handle
    end

    if primary.values.compact.any?
      "CURRENT ACTIVE PAYMENT HANDLES (use these EXACT values when asked — do not invent or use old handles):\n" +
        primary.map { |p, h| "#{p}: #{h}" }.join("\n")
    else
      no_payment_handles_prompt_text
    end
  rescue StandardError => e
    Rails.logger.warn("[AiReply] payment_handles_context #{e.class}: #{e.message}")
    ''
  end

  def no_payment_handles_prompt_text
    'NO PAYMENT HANDLES ARE CURRENTLY AVAILABLE. If a customer asks where to send money, tell them politely ' \
      "that you're checking with the team and a human will follow up shortly. Do NOT make up a handle. " \
      'Add a note that escalation is needed.'
  end

  def record_payment_handle_success!(account, platform, recip_normalized)
    return if account.blank? || platform.to_s.strip.empty? || recip_normalized.to_s.strip.empty?
    return unless PaymentHandle::PLATFORMS.include?(platform.to_s)

    handle = account.payment_handles.where(platform: platform).find { |ph| ph.normalized_handle == recip_normalized }
    if defined?(Payments::FailoverManager) && handle
      Payments::FailoverManager.new(handle).reset!
    end
  rescue StandardError => e
    Rails.logger.warn("[ReplyService] record_payment_handle_success #{e.class}: #{e.message}")
  end

  # it6 (A1c) — ACTIVE agent_policy promotions (authoritative; the ONLY bonus/referral/
  # cashout terms Bella may state). '' when no policy configured.
  def agent_policy_prompt_section
    resolver = policy_resolver
    return '' unless resolver&.configured?

    lines = ["\nACTIVE PROMOTIONS & POLICY (state ONLY these — never invent, negotiate, or promise to add):"]
    active = resolver.active_bonuses
    if active.any?
      active.each do |b|
        name = b['name'].to_s.strip
        bits = []
        bits << "#{b['percent']}% bonus" if b['percent']
        bits << "min deposit $#{b['min_deposit']}" if b['min_deposit']
        bits << "max deposit $#{b['max_deposit']}" if b['max_deposit']
        bits << "max bonus $#{b['cap']}" if b['cap']
        lines << "  - #{name.empty? ? 'Bonus' : name}#{bits.any? ? ": #{bits.join(', ')}" : ''}"
      end
    elsif resolver.bonuses_configured?
      lines << "  - No bonus is active right now. If asked, say you'll check the current promo — do NOT offer a percentage."
    end
    if resolver.referral_configured?
      r = resolver.referral
      extra = []
      extra << "after deposit ##{r['trigger_deposit_number']}" if r['trigger_deposit_number']
      extra << "cap $#{r['cap']}" if r['cap']
      lines << "  - Referral: #{r['percent']}%#{extra.any? ? " (#{extra.join(', ')})" : ''}"
    end
    if resolver.cashout_configured?
      c = resolver.cashout
      cb = []
      cb << "min $#{c['min']}" if c['min']
      cb << "max $#{c['max']}" if c['max']
      cb << "playthrough #{c['playthrough_min']}x-#{c['playthrough_max']}x" if c['playthrough_min'] || c['playthrough_max']
      lines << "  - Cashout: #{cb.join(', ')}" if cb.any?
      lines << "  - Cashout terms: #{c['terms_text']}" if c['terms_text'].to_s.strip.length.positive?
    end
    lines << '  RULE: if a customer wants more, a different bonus, or one not listed/active now — say you will confirm. NEVER invent a number, negotiate, or promise to add/throw in a bonus.'
    lines.join("\n")
  rescue StandardError => e
    Rails.logger.warn("[ReplyService] agent_policy_prompt_section failed: #{e.class}: #{e.message}")
    ''
  end

  # Build dynamic rules from agent_policy (it6 — authoritative) + game_rules DB (per-game fallback).
  def dynamic_game_rules_prompt
    policy_section = agent_policy_prompt_section
    rules_section =
      begin
        rules = GameRule.where(account_id: account_id).includes(:game)
        if rules.empty?
          ''
        else
          resolver = policy_resolver
          policy_owns_bonus = resolver&.bonuses_configured? || false
          policy_owns_cashout = resolver&.cashout_configured? || false
          lines = ["\nGAME RULES (from Settings — follow these, not any older rules):"]
          rules.each do |r|
            game_name = r.game&.name || r.game&.slug || 'Unknown'
            parts = ["#{game_name}:"]
            parts << "Bonus: #{r.deposit_bonus_percentage}%" if r.deposit_bonus_enabled && !policy_owns_bonus
            parts << "Min deposit for bonus: $#{r.deposit_bonus_min_amount}" if r.deposit_bonus_enabled && !policy_owns_bonus
            parts << "Cashout: #{r.cashout_min_multiplier}x-#{r.cashout_max_multiplier}x, max $#{r.cashout_max_amount}" if r.cashout_enabled && !policy_owns_cashout
            parts << "Freeplay: $#{r.freeplay_amount}/day" if r.freeplay_enabled
            parts << "Rules: #{r.cashout_rules_text}" if r.cashout_rules_text.present?
            next if parts.size == 1

            lines << "  " + parts.join(" | ")
          end
          lines.size > 1 ? lines.join("\n") : ''
        end
      rescue StandardError => e
        Rails.logger.error("[ReplyService] dynamic_game_rules_prompt failed: #{e.message}")
        ''
      end
    [policy_section, rules_section].reject { |s| s.to_s.strip.empty? }.join("\n")
  end

  def fetch_rag_examples(customer_text, account_id, intent_label = nil)
    begin
      pref = ReplyPreference.for_account(account_id)
      return [] unless pref.use_rag_examples
      example_count = pref.rag_example_count || 3
    rescue StandardError => e
      Rails.logger.error("[ReplyService] ReplyPreference lookup failed: #{e.message}")
      example_count = 3
    end

    begin
      results = if defined?(BellaRag::IntentRetriever) && BellaRag::IntentRetriever.respond_to?(:retrieve)
                  BellaRag::IntentRetriever.retrieve(
                    text: customer_text,
                    account_id: account_id,
                    top_k: example_count,
                    threshold: 0.30
                  )
                elsif defined?(BellaRagPair)
                  rag_account = Account.find_by(id: account_id)
                  rag_industry_slug = rag_account&.industry_slug || 'sweepstakes'
                  BellaRagPair.search_similar(
                    customer_text.to_s,
                    limit: example_count,
                    account_id: account_id,
                    industry_slug: rag_industry_slug
                  ).map do |pair|
                    {
                      customer_text: pair.customer_text,
                      cashier_text: pair.cashier_text,
                      real_intent: pair.real_intent
                    }
                  end
                else
                  []
                end

      examples = Array(results).map do |r|
        {
          customer: r[:customer_text] || r['customer_text'],
          cashier: r[:cashier_text] || r['cashier_text'],
          intent: r[:real_intent] || r['real_intent']
        }
      end.compact

      Rails.logger.info("[ReplyService] RAG examples: #{examples.length} found for: #{customer_text.to_s.truncate(50)}")
      examples
    rescue StandardError => e
      Rails.logger.error("[ReplyService] RAG example fetch failed: #{e.message}")
      []
    end
  end

  def build_rag_enhanced_prompt(base_prompt, rag_examples, reply_pref = nil)
    return base_prompt if reply_pref.nil? && rag_examples.blank?

    examples_section = if rag_examples.present?
      examples_text = rag_examples.map do |ex|
        "Customer: #{ex[:customer]}\nCashier: #{ex[:cashier]}"
      end.join("\n---\n")

      "\nHere are examples of how real cashiers reply to similar messages:\n#{examples_text}\n\nNow reply to this customer in the SAME style as the examples above."
    else
      ""
    end

    tone = reply_pref&.reply_tone || 'casual'
    max_lines = reply_pref&.max_reply_lines || 2
    use_emojis = reply_pref&.use_emojis != false
    sign_off = reply_pref&.sign_off_text

    tone_instruction = case tone
    when 'casual'
      "Reply like a real cashier texting on shift. Keep it short, warm, human."
    when 'professional'
      "Reply professionally but briefly. No corporate speak."
    when 'minimal'
      "Reply with absolute minimum words. Just the facts."
    else
      "Reply like a real cashier texting on shift."
    end

    <<~PROMPT.strip
      #{tone_instruction}
      Max #{max_lines} lines. #{use_emojis ? 'Emojis OK.' : 'No emojis.'}
      #{"Sign off with: #{sign_off}" if sign_off.present?}
      #{examples_section}

      Never admit you are AI. Never use bullet points. Never say "certainly" or "great question".

      #{base_prompt}
    PROMPT
  end

  # ─────────────────────────────────────────────────────────
  # RAG: retrieve top-K similar past customer→cashier pairs
  # from bella_rag_pairs (Phase 2 corpus, 73k real examples)
  # and format as a system-prompt block. Returns "" if the
  # feature flag is off, on any error, or if no matches found.
  # Latency budget: ~250-400ms (Voyage embed + HNSW search).
  # Always fails CLOSED — never blocks a reply.
  # ─────────────────────────────────────────────────────────
  def retrieve_rag_examples_block(latest_customer_text)
    # Disabled — replaced by fetch_rag_examples + build_rag_enhanced_prompt (ReplyPreference-based)
    return ''

    unless ENV['BELLA_RAG_ENABLED'].to_s == 'true'
      Rails.logger.info('[RAG] skipped — BELLA_RAG_ENABLED is not true')
      return ''
    end
    return '' if latest_customer_text.to_s.strip.empty?
    return '' unless defined?(BellaRagPair)

    msg_snippet = latest_customer_text.to_s.strip[0, 120]

    # Build query mirroring how Phase 1 parser embedded documents:
    # last 2 turns of context + the live customer message.
    history = Array(@conversation_history_for_llm).last(2)
    query_parts = history.map do |h|
      role = h['role'] == 'user' ? 'customer' : 'cashier'
      "[#{role}]: #{h['content'].to_s[0, 400]}"
    end
    query_parts << "[customer]: #{latest_customer_text.to_s[0, 800]}"
    query_text = query_parts.join("\n")

    started = Time.now
    rag_account = Account.find_by(id: account_id)
    rag_industry_slug = rag_account&.industry_slug || 'sweepstakes'
    results = if @rag_cached_query_vec.present?
                BellaRagPair.search_similar_with_distance(
                  query_vec: @rag_cached_query_vec,
                  limit: 5,
                  industry: 'sweepstakes',
                  persona: 'bella',
                  account_id: account_id,
                  industry_slug: rag_industry_slug
                ).map { |h| h[:pair] }
              else
                BellaRagPair.search_similar(
                  query_text,
                  limit: 5,
                  industry: 'sweepstakes',
                  persona: 'bella',
                  account_id: account_id,
                  industry_slug: rag_industry_slug
                )
              end
    elapsed_ms = ((Time.now - started) * 1000).to_i

    if results.blank?
      Rails.logger.info(
        "[RAG] Found 0 similar pairs for message: #{msg_snippet.inspect} conv=#{@conversation_id} elapsed=#{elapsed_ms}ms"
      )
      return ''
    end

    Rails.logger.info(
      "[RAG] Found #{results.size} similar pairs for message: #{msg_snippet.inspect} conv=#{@conversation_id} elapsed=#{elapsed_ms}ms"
    )

    lines = ['', '═══════════════════════════════════════════════════════════',
             'SIMILAR PAST EXCHANGES — your real prior replies to similar messages.',
             'Use as STYLE and STRATEGY reference. Do NOT copy verbatim.',
             '']
    results.each_with_index do |r, i|
      lines << "EXAMPLE #{i + 1}:"
      lines << "  Customer: #{r.customer_text.to_s[0, 300].gsub("\n", ' ')}"
      lines << "  You replied: #{r.cashier_text.to_s[0, 400].gsub("\n", ' ')}"
      lines << ''
    end
    lines << '═══════════════════════════════════════════════════════════'
    lines.join("\n")
  rescue StandardError => e
    Rails.logger.warn(
      "[AiReply][RAG] failed conv=#{@conversation_id} err=#{e.class}: #{e.message[0, 200]}"
    )
    ''
  end
end
