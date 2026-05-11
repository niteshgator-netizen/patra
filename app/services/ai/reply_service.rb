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
  HISTORY_LIMIT = 5
  HTTP_TIMEOUT = 30
  SKIP_LABEL = 'ai-off'.freeze
  # If the freshest message in the conversation is older than this, the
  # customer has likely moved on — a delayed AI reply would feel weird, so
  # we bail rather than send one.
  MESSAGE_FRESHNESS_WINDOW = 10.minutes
  # `created_at` must be a real Unix second for the freshness gate. Values below
  # this (e.g. `String#to_i` on ISO8601 → 2026) are treated as unusable for staleness.
  FRESHNESS_UNIX_MIN = 946_684_800 # 2000-01-01 UTC
  # Customer messages that match these exactly (case-insensitive, trimmed)
  # short-circuit Anthropic — they don't need a model call.
  SIMPLE_GREETINGS = %w[hi hey hello hii heyy heyyy sup yo].freeze
  GREETING_REPLY = 'yo whats good'.freeze
  # Redis cache for canned-response lookups. 10 min TTL is short enough that
  # ops edits in the Chatwoot UI propagate quickly, long enough to absorb the
  # per-message fetch traffic.
  CANNED_CACHE_PREFIX = 'patra:canned:'.freeze
  CANNED_CACHE_TTL = 600
  # Single-quoted heredoc — no interpolation, so apostrophes inside the prompt
  # (e.g. "won't") and the literal escalation phrase don't need escaping.
  SYSTEM_PROMPT = <<~'PROMPT'.freeze
    YOU ARE BELLA — a real human game loader at this business.
    You are NOT an AI. You are a person texting customers from your phone.

    NEVER SAY THESE (instant fail):
    - 'How can I help you today?'
    - 'How may I assist you?'
    - 'I'd be happy to help'
    - 'Is there anything else?'
    - 'Feel free to ask'
    - 'Thank you for reaching out'
    - Any corporate or AI-sounding phrase

    REPLY STYLE:
    - Talk like a real friend texting fast
    - Max 1-2 short lines per reply (under 20 words ideal)
    - Lowercase ok, skip periods at end of casual replies
    - One topic per reply only
    - Most replies have ZERO emoji (use sparingly when genuinely fitting)
    - Use casual words: 'yo', 'hey', 'sure thing', 'gotcha', 'lemme', 'np'

    GREETINGS (when customer says hi/hey/yo/sup):
    ✅ 'yo whats good'
    ✅ 'hey! you loading today?'
    ✅ 'sup, what game we playing'
    ✅ 'hey hey, what we doing today'
    ✅ 'yo'
    ❌ 'Hello! How can I help you today?' (FORBIDDEN)
    ❌ 'Hi! Welcome! 😊 How can I assist?' (FORBIDDEN)

    EXAMPLES:
    Customer: 'i wanna load juwa'
    ✅ 'aight whats your juwa username'
    ✅ 'sure thing, username?'

    Customer: 'how do i pay'
    ✅ 'cashapp, chime, venmo or paypal — which?'

    Customer: 'send cashapp'
    ✅ 'send to $hustle09 and drop the screenshot when ur done'

    Customer: 'what bonus'
    ✅ 'for $20+ i got 25% bonus for ya'

    EMOJI RULE:
    Default = ZERO emojis. Only use ONE emoji when it actually fits naturally:
    - New player welcome: 🎉 (once)
    - Big win/exciting: 🔥 (once)
    - Never two emojis. Never on every message.

    BUSINESS KNOWLEDGE:

    WHAT WE DO:
    We are a game loading and redemption service. Customers send us money,
    we load it onto their game account. When they win, they request cashout
    (redeem) and we pay them out via their preferred payment method.

    PAYMENT METHODS WE ACCEPT:
    Cash App, PayPal, Chime, Venmo, Varo, Google Pay, Apple Pay, Visa,
    Mastercard, and any major credit/debit card. We accept ALL payment methods.

    <<<PAYMENT_INFO_SECTION>>>

    GAMES WE SUPPORT:
    Juwa, Juwa 2.0, Orionstar, Milkyway, Firekirin, Gamevault, Gameroom,
    Moolah, Casino Ignite, Vegas Sweeps, Pandamaster, Spin City, Vblink,
    Mafia, Cash Machine, Ultra Panda, Billion Balls, Yolo, Vegas Roll,
    Cash Frenzy, Mr All In One, and many more. Ask us about any game not listed.

    DEPOSIT BONUS RULES:
    - Deposits under $5: No bonus
    - Deposits $5 and over: 20% to 40% bonus
      * Regular players: 20-30% bonus
      * Loyal/active players who keep playing: up to 30-40% bonus
      * If a player only plays at 30% bonus and wont play for less,
        and they are a good player, we can give 30%
      * Use judgment based on customer history

    CASHOUT/REDEEM RULES:
    For deposits over $5:
      - Minimum cashout: 4x the deposit amount
      - Maximum cashout: 10x the deposit amount

    For deposits under $5:
      - Minimum cashout: 4x the deposit amount
      - Maximum cashout: 5x the deposit amount

    For referral bonus:
      - Minimum: 4x the referral amount
      - Maximum: 5x the referral amount

    For $2 or $3 Freeplay:
      - Hit 50+ points: get $10 in-game credit
      - Hit 60+ points: get $10 cashout to Cash App/Chime/Venmo etc.

    REFERRAL BONUS PROGRAM:
    - Earn up to 100% referral bonus
    - How it works: Refer a friend -> they message us confirming who referred them
      -> they make 2 deposits using their own payment method
      -> referrer earns 100% of the 2nd deposit amount
    - Example: Friend deposits $100 twice = $100 bonus for referrer
    - Requirements: FB account 1.5+ years old, payment method matches ID,
      no self-referrals or fake accounts

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
    - Short is always better than long
  PROMPT

  # Case-insensitive substring matches against the model's reply. We list both
  # the canonical phrase and looser variants because the model may shorten or
  # re-case the escalation cue ("Let me check on that.", "One moment please").
  ESCALATION_PHRASES = [
    'let me check on that for you, one moment!',
    'let me check on that',
    'one moment'
  ].freeze

  # Tiered sentiment detection. Level 1 = impatience (AI replies warmly).
  # Level 2 = real anger (AI replies with apology + solution attempt).
  # Level 3 = explicit human request, OR Level 2 anger AFTER we already
  # apologized → escalate to a human without another AI turn.
  ANGER_LEVEL_1_KEYWORDS = [
    'where is', 'still waiting', 'taking long', 'taking forever',
    'not received', 'havent received', "haven't received",
    'why', 'when'
  ].freeze
  ANGER_LEVEL_2_KEYWORDS = [
    'scam', 'fraud', 'cheated', 'stole', 'fake', 'angry', 'pissed',
    'wtf', 'fuck', 'shit', 'ripped off', 'never again',
    'fix this now', 'lawsuit', 'report'
  ].freeze
  ANGER_LEVEL_3_KEYWORDS = [
    'real person', 'human agent', 'speak to manager', 'this is bs',
    'reporting you'
  ].freeze
  # Markers we look for in the most recent assistant message — if we already
  # apologized and the customer is still angry, that's a Level 2 → escalate.
  APOLOGY_MARKERS = ['sorry', 'apologize', 'frustrated', 'my bad'].freeze

  # Customer phrasing that should trigger a forced "send the BoltPay link"
  # behavior — keyed off the payment_info canned response.
  PAYMENT_LINK_KEYWORDS = [
    'card', 'credit', 'debit', 'visa', 'mastercard', 'apple pay',
    'google pay', 'bolt', 'secure link', 'online pay'
  ].freeze

  def initialize(conversation_id, account_id: nil)
    @conversation_id = conversation_id
    @bridge_account_id = account_id
  end

  def call
    return nil if @conversation_id.blank?
    return log_and_nil('XAI_API_KEY not configured') if api_key.blank?
    return log_and_nil('CHATWOOT_BRIDGE_API_TOKEN not configured') if chatwoot_token.blank?

    # Pulled up so the freshness check (which needs @latest_timestamp from the
    # messages payload) can run before any other AI work.
    messages = build_messages

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

    # Tiered sentiment handling — see detect_anger_level. Level 3 hands off
    # to a human immediately; Levels 1 & 2 keep the AI in the loop but inject
    # an empathy hint into the prompt so the reply is appropriately warm.
    sentiment_level = detect_anger_level(messages)
    if sentiment_level == :escalate
      escalate_to_human(messages, 'angry after AI attempt')
      return nil
    end
    empathy_hint = empathy_hint_for(sentiment_level)

    # Cheap-path canned hello — bypasses Anthropic entirely for one-word
    # greetings like "hi"/"yo".
    last_message = messages.last&.dig('content').to_s.downcase.strip
    return GREETING_REPLY if SIMPLE_GREETINGS.include?(last_message)

    payment_info = fetch_payment_info
    training_info = fetch_ai_training
    persona_info = fetch_ai_persona
    player_profile = fetch_player_profile
    canned_responses_text = fetch_all_canned_responses
    payment_link_hint = needs_payment_link?(messages)
    system_prompt = build_system_prompt(
      payment_info,
      training_info,
      persona_info,
      player_profile,
      canned_responses_text,
      payment_link_hint
    )
    system_prompt = "#{system_prompt}\nSITUATION: #{empathy_hint}\n" if empathy_hint

    reply = invoke_anthropic(messages, system_prompt)
    return nil if reply.blank?

    if escalation?(reply)
      post_escalation_note(messages)
      return nil
    end

    Rails.logger.info("[AiReply] drafted conversation=#{@conversation_id} chars=#{reply.length}")
    reply
  rescue StandardError => e
    Rails.logger.error("[AiReply] failed conversation=#{@conversation_id} #{e.class}: #{e.message}")
    nil
  end

  private

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
      timeout: HTTP_TIMEOUT
    )

    unless response.success?
      Rails.logger.error("[AiReply] message list HTTP #{response.code} conversation=#{@conversation_id}: #{response.body}")
      return []
    end

    payload = Array(response.parsed_response['payload'])
    # Captured for the freshness check in `call`. Use the raw payload (every
    # message type) so activity events still count as "the conversation is alive".
    @latest_timestamp = payload.map { |m| message_created_at_unix(m['created_at']) }.max
    # Chatwoot serializes message_type as an integer: 0 = incoming, 1 = outgoing.
    # 2/3 are activity/template — skip those, they're not part of the conversation.
    history = payload
              .select { |m| (t = chat_message_type(m)) && [0, 1].include?(t) }
              .reject { |m| m['content'].to_s.strip.empty? }
              .sort_by { |m| message_created_at_unix(m['created_at']) }
              .last(HISTORY_LIMIT)
              .map do |m|
                t = chat_message_type(m)
                { 'role' => t == 0 ? 'user' : 'assistant', 'content' => m['content'].to_s }
              end

    # Anthropic requires the first message to be `user`. Drop any leading
    # assistant turns so the API doesn't 400 with a role-ordering error.
    history.shift while history.any? && history.first['role'] != 'user'
    history
  end

  # Builds a one-line summary about the contact behind this conversation so
  # the model can personalize (greet by name, recognize returning players).
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
    # messages and persist the result for future calls.
    game_username = custom_attrs['game_username'].presence ||
                    additional_attrs['game_username'].presence ||
                    store_player_username(contact_id)

    # 3. Past conversations → count = "previous interactions"
    convos_response = HTTParty.get(
      "#{base_url}/api/v1/accounts/#{account_id}/contacts/#{contact_id}/conversations",
      headers: chatwoot_headers,
      timeout: HTTP_TIMEOUT
    )
    conversations_count = convos_response.success? ? Array(convos_response.parsed_response['payload']).length : 0

    parts = []
    parts << "Player name: #{name}" if name.present?
    parts << "Customer's game username: #{game_username}" if game_username.present?
    parts << "Previous interactions: #{conversations_count}"
    notes = (additional_attrs['notes'] || custom_attrs['notes']).to_s.strip
    parts << "Notes: #{notes}" if notes.present?
    parts.join("\n")
  rescue StandardError => e
    Rails.logger.warn("[AiReply] player profile fetch error conversation=#{@conversation_id} #{e.class}: #{e.message}")
    ''
  end

  # Scans the most recent 20 messages for a self-declared username pattern
  # ("my username is X", "username: X", "my id is X", "my tag is X") and, if
  # found, PATCHes the contact's custom_attributes.game_username so future
  # replies can address the player by their in-game handle. Chatwoot merges
  # custom_attributes on update, so this is a safe partial write.
  # Returns the detected username on success, nil on no-match or any failure.
  USERNAME_PATTERN = /
    (?:my\s+(?:game\s+)?username\s+is|
       my\s+(?:game\s+)?username\s*:|
       (?:game\s+)?username\s+is|
       (?:game\s+)?username\s*:|
       username\s*:|
       my\s+id\s+is|
       my\s+tag\s+is)
    \s*([^\s.,;:!?]+)
  /ix
  USERNAME_SCAN_LIMIT = 20

  # Username-only replies (common behavior: player sends just their handle).
  # Kept conservative to avoid misclassifying "juwa" or "cashapp" as a
  # game username.
  HANDLE_ONLY_PATTERN = /\A[a-zA-Z0-9][a-zA-Z0-9_.-]{2,24}\z/.freeze
  HANDLE_NEEDS_DIGIT_OR_SEPARATOR = /[0-9_.-]/.freeze
  HANDLE_BLACKLIST = %w[
    hi hey hello hii heyy heyyy sup yo
    cashapp venmo paypal chime
    card credit debit visa mastercard
    googlepay appley pay applepay
  ].freeze

  def store_player_username(contact_id)
    return nil if contact_id.blank?

    messages_response = HTTParty.get(
      "#{base_url}/api/v1/accounts/#{account_id}/conversations/#{@conversation_id}/messages",
      headers: chatwoot_headers,
      timeout: HTTP_TIMEOUT
    )
    return nil unless messages_response.success?

    recent = Array(messages_response.parsed_response['payload'])
             .select { |m| chat_message_type(m) == 0 } # only customer/incoming messages
             .sort_by { |m| message_created_at_unix(m['created_at']) }
             .last(USERNAME_SCAN_LIMIT)

    # Iterate newest first so a later correction wins over an earlier mention.
    username = nil
    recent.reverse_each do |m|
      content = m['content'].to_s.strip
      next if content.empty?

      match = content.match(USERNAME_PATTERN)
      if match
        username = match[1].strip
        break
      end

      # Normalize handle-ish text like "@handle!" -> "handle".
      handle_candidate = content.sub(/\A[@#]/, '')
      handle_candidate = handle_candidate.sub(/[.,;:!?]+\z/, '')

      downcased = handle_candidate.downcase
      next if HANDLE_BLACKLIST.include?(downcased)

      # Handle-only detection: "juwa_123", "hustle09", etc.
      if handle_candidate.match?(HANDLE_ONLY_PATTERN) && handle_candidate.match?(HANDLE_NEEDS_DIGIT_OR_SEPARATOR)
        username = handle_candidate
        break
      end
    end
    return nil if username.blank?

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
  rescue StandardError => e
    Rails.logger.warn("[AiReply] store_player_username error contact=#{contact_id} #{e.class}: #{e.message}")
    nil
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
      Rails.logger.warn("[AiReply] payment_info canned response not found in account=#{account_id}")
      return ''
    end

    content = match['content'].to_s
    write_canned_cache('payment_info', content)
    content
  rescue StandardError => e
    Rails.logger.warn("[AiReply] payment_info fetch error #{e.class}: #{e.message}")
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

  def build_system_prompt(payment_info, training_info = '', persona_info = '', player_profile = '', canned_responses = '', needs_payment_link = false)
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

    prompt = SYSTEM_PROMPT.sub('<<<PAYMENT_INFO_SECTION>>>', section)

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

        Use this to personalize your response. If you know their name
        use it naturally. If they are a returning player treat them warmly.
        If CURRENT PLAYER INFO already includes a line starting with
        "Customer's game username:", do not ask for it again. If the
        username is missing, ask for it once (only one question). After
        the customer provides it, never ask again. Always greet returning
        players by username.

        GREETING RULES:
        - If "Previous interactions: 1" (their first conversation): warm
          welcome ("Hey! Welcome 😊"), ask their game username, briefly
          mention "we load 20+ game platforms" — keep to 1 line.
        - Otherwise: skip intro entirely. Greet by username if known,
          reference last_game if known, get to the action fast.
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

    prompt
  end

  # ---------- Anthropic ----------

  def invoke_anthropic(messages, system_prompt)
    response = HTTParty.post(
      XAI_URL,
      headers: {
        'Authorization' => "Bearer #{api_key}",
        'Content-Type' => 'application/json'
      },
      body: {
        model: MODEL,
        max_tokens: MAX_TOKENS,
        # xAI uses OpenAI's wire format — system prompt goes in as the first
        # message instead of a top-level `system` field.
        messages: [{ role: 'system', content: system_prompt }, *messages]
      }.to_json,
      timeout: HTTP_TIMEOUT
    )

    unless response.success?
      Rails.logger.error("[AiReply] xAI HTTP #{response.code} conversation=#{@conversation_id}: #{response.body}")
      return nil
    end

    text = response.parsed_response.dig('choices', 0, 'message', 'content')
    if text.blank?
      Rails.logger.warn("[AiReply] xAI returned no text conversation=#{@conversation_id} body=#{response.body}")
      return nil
    end

    text
  end

  # ---------- Escalation ----------

  def escalation?(reply)
    downcased = reply.to_s.downcase
    ESCALATION_PHRASES.any? { |phrase| downcased.include?(phrase) }
  end

  # Returns :escalate / :level_2 / :level_1 / nil based on the latest user
  # message. :escalate triggers an immediate hand-off; :level_1 and :level_2
  # keep the AI in the loop but signal the prompt to be more empathetic.
  def detect_anger_level(messages)
    user_msgs = messages.select { |m| m['role'] == 'user' }
    return nil if user_msgs.empty?

    latest = user_msgs.last['content'].to_s.downcase

    return :escalate if matches_any_keyword?(latest, ANGER_LEVEL_3_KEYWORDS)

    if matches_any_keyword?(latest, ANGER_LEVEL_2_KEYWORDS)
      last_assistant = messages.select { |m| m['role'] == 'assistant' }.last
      if last_assistant
        prior = last_assistant['content'].to_s.downcase
        return :escalate if APOLOGY_MARKERS.any? { |w| prior.include?(w) }
      end
      return :level_2
    end

    return :level_1 if matches_any_keyword?(latest, ANGER_LEVEL_1_KEYWORDS)

    nil
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
      'CUSTOMER IS FRUSTRATED. Apologize warmly and try to solve their problem. Be empathetic. No emojis.'
    when :level_1
      'CUSTOMER SEEMS IMPATIENT. Be warm and fast to acknowledge their concern. No emojis here.'
    end
  end

  # Posts a private note flagging an angry customer, then adds both ai-off and
  # needs-human labels to the conversation. `bulk_actions/process` is what
  # Chatwoot's own bulk label endpoint uses — we hit the REST API the same way.
  def escalate_to_human(messages, matched_keyword)
    Rails.logger.info("[AiReply] escalating angry-customer conversation=#{@conversation_id} match=#{matched_keyword}")

    last_three = messages.select { |m| m['role'] == 'user' }
                         .last(3)
                         .map { |m| "- #{m['content'].to_s.strip}" }
                         .join("\n")
    note = "🚨 ANGRY CUSTOMER — Reason: #{matched_keyword}\n" \
           "Sentiment: negative. Last 3 messages:\n#{last_three}"

    HTTParty.post(
      "#{base_url}/api/v1/accounts/#{account_id}/conversations/#{@conversation_id}/messages",
      headers: chatwoot_headers.merge('Content-Type' => 'application/json'),
      body: { content: note, message_type: 'outgoing', private: true }.to_json,
      timeout: HTTP_TIMEOUT
    )

    HTTParty.post(
      "#{base_url}/api/v1/accounts/#{account_id}/bulk_actions",
      headers: chatwoot_headers.merge('Content-Type' => 'application/json'),
      body: { type: 'Conversation', ids: [@conversation_id], labels: { add: %w[ai-off needs-human] } }.to_json,
      timeout: HTTP_TIMEOUT
    )
  rescue StandardError => e
    Rails.logger.error("[AiReply] escalate_to_human failed conversation=#{@conversation_id} #{e.class}: #{e.message}")
  end

  # True if the latest user message mentions a card / pay-link keyword.
  # Drives the "you MUST send the BoltPay link" directive in the prompt.
  def needs_payment_link?(messages)
    last_user = messages.reverse.find { |m| m['role'] == 'user' }
    return false unless last_user

    text = last_user['content'].to_s.downcase
    PAYMENT_LINK_KEYWORDS.any? { |kw| text.include?(kw) }
  end

  # Drops a private note onto the conversation so a human agent picks it up
  # without the customer seeing it. private:true also means our own
  # FbReplyController will skip the resulting message_created webhook (via
  # `private_message?`), so the note never leaks back out to Facebook.
  def post_escalation_note(history)
    last_user_message = history.reverse.find { |m| m['role'] == 'user' }&.dig('content').to_s

    response = HTTParty.post(
      "#{base_url}/api/v1/accounts/#{account_id}/conversations/#{@conversation_id}/messages",
      headers: chatwoot_headers.merge('Content-Type' => 'application/json'),
      body: {
        content: "🤖 AI escalation: Customer needs human attention - #{last_user_message}",
        message_type: 'outgoing',
        private: true
      }.to_json,
      timeout: HTTP_TIMEOUT
    )

    if response.success?
      Rails.logger.info("[AiReply] escalated conversation=#{@conversation_id}")
    else
      Rails.logger.error("[AiReply] escalation note HTTP #{response.code} conversation=#{@conversation_id}: #{response.body}")
    end
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
end
