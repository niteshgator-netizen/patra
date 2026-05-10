# Generates a draft reply for a Chatwoot conversation using the Anthropic
# Messages API. Returns the reply text on success, or nil when:
#   - the conversation carries the `ai-off` label (opt-out)
#   - the message history can't be fetched
#   - no usable history exists
#   - the Anthropic call fails for any reason
#
# Configuration (all read at call time):
#   ANTHROPIC_API_KEY            — required
#   CHATWOOT_BRIDGE_API_TOKEN    — required (to read conversation + messages)
#   CHATWOOT_BRIDGE_BASE_URL     — defaults to https://patrahq.com
#   CHATWOOT_BRIDGE_ACCOUNT_ID   — defaults to 2
class Ai::ReplyService
  ANTHROPIC_URL = 'https://api.anthropic.com/v1/messages'.freeze
  ANTHROPIC_VERSION = '2023-06-01'.freeze
  MODEL = 'claude-sonnet-4-6'.freeze
  MAX_TOKENS = 150
  HISTORY_LIMIT = 5
  HTTP_TIMEOUT = 30
  SKIP_LABEL = 'ai-off'.freeze
  # If the freshest message in the conversation is older than this, the
  # customer has likely moved on — a delayed AI reply would feel weird, so
  # we bail rather than send one.
  MESSAGE_FRESHNESS_WINDOW = 10.minutes
  # Customer messages that match these exactly (case-insensitive, trimmed)
  # short-circuit Anthropic — they don't need a model call.
  SIMPLE_GREETINGS = %w[hi hey hello hii heyy heyyy sup yo].freeze
  GREETING_REPLY = "Hey! 😊 How can I help you today?".freeze
  # Redis cache for canned-response lookups. 10 min TTL is short enough that
  # ops edits in the Chatwoot UI propagate quickly, long enough to absorb the
  # per-message fetch traffic.
  CANNED_CACHE_PREFIX = 'patra:canned:'.freeze
  CANNED_CACHE_TTL = 600
  # Single-quoted heredoc — no interpolation, so apostrophes inside the prompt
  # (e.g. "won't") and the literal escalation phrase don't need escaping.
  SYSTEM_PROMPT = <<~'PROMPT'.freeze
    You are a helpful customer support agent for an online gaming platform.
    You talk casually and friendly like a real human agent - use natural
    conversational English, occasional short responses, and never sound
    robotic or formal. Make small natural variations in how you phrase things.

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

  def initialize(conversation_id)
    @conversation_id = conversation_id
  end

  def call
    return nil if @conversation_id.blank?
    return log_and_nil('ANTHROPIC_API_KEY not configured') if api_key.blank?
    return log_and_nil('CHATWOOT_BRIDGE_API_TOKEN not configured') if chatwoot_token.blank?

    # Pulled up so the freshness check (which needs @latest_timestamp from the
    # messages payload) can run before any other AI work.
    messages = build_messages

    if @latest_timestamp.to_i.positive? && (Time.current - Time.at(@latest_timestamp.to_i)) > MESSAGE_FRESHNESS_WINDOW
      Rails.logger.info("[AiReply] skipping old message conv=#{@conversation_id}")
      return nil
    end

    return log_and_nil("no usable history conversation=#{@conversation_id}") if messages.empty?

    if ai_disabled?
      Rails.logger.info("[AiReply] skipping conversation=#{@conversation_id} (label='#{SKIP_LABEL}')")
      return nil
    end

    # Cheap-path canned hello — bypasses Anthropic entirely for one-word
    # greetings like "hi"/"yo".
    last_message = messages.last&.dig('content').to_s.downcase.strip
    return GREETING_REPLY if SIMPLE_GREETINGS.include?(last_message)

    payment_info = fetch_payment_info
    training_info = fetch_ai_training
    persona_info = fetch_ai_persona
    system_prompt = build_system_prompt(payment_info, training_info, persona_info)

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
    @latest_timestamp = payload.map { |m| m['created_at'].to_i }.max
    # Chatwoot serializes message_type as an integer: 0 = incoming, 1 = outgoing.
    # 2/3 are activity/template — skip those, they're not part of the conversation.
    history = payload
              .select { |m| [0, 1].include?(m['message_type'].to_i) }
              .reject { |m| m['content'].to_s.strip.empty? }
              .sort_by { |m| m['created_at'].to_i }
              .last(HISTORY_LIMIT)
              .map { |m| { 'role' => m['message_type'].to_i == 0 ? 'user' : 'assistant', 'content' => m['content'].to_s } }

    # Anthropic requires the first message to be `user`. Drop any leading
    # assistant turns so the API doesn't 400 with a role-ordering error.
    history.shift while history.any? && history.first['role'] != 'user'
    history
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

  def build_system_prompt(payment_info, training_info = '', persona_info = '')
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
      PERSONA
      prompt = "#{persona_section}\n\n#{prompt}"
    end

    return prompt if training_info.to_s.strip.empty?

    training_section = <<~TRAINING.strip
      ADDITIONAL BUSINESS RULES (highest priority - follow these exactly):
      #{training_info}
    TRAINING

    "#{prompt}\n#{training_section}\n"
  end

  # ---------- Anthropic ----------

  def invoke_anthropic(messages, system_prompt)
    response = HTTParty.post(
      ANTHROPIC_URL,
      headers: {
        'x-api-key' => api_key,
        'anthropic-version' => ANTHROPIC_VERSION,
        'content-type' => 'application/json'
      },
      body: {
        model: MODEL,
        max_tokens: MAX_TOKENS,
        system: system_prompt,
        messages: messages
      }.to_json,
      timeout: HTTP_TIMEOUT
    )

    unless response.success?
      Rails.logger.error("[AiReply] Anthropic HTTP #{response.code} conversation=#{@conversation_id}: #{response.body}")
      return nil
    end

    text = response.parsed_response.dig('content', 0, 'text')
    if text.blank?
      Rails.logger.warn("[AiReply] Anthropic returned no text conversation=#{@conversation_id} body=#{response.body}")
      return nil
    end

    text
  end

  # ---------- Escalation ----------

  def escalation?(reply)
    downcased = reply.to_s.downcase
    ESCALATION_PHRASES.any? { |phrase| downcased.include?(phrase) }
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
    ENV.fetch('ANTHROPIC_API_KEY', '').to_s
  end

  def base_url
    @base_url ||= ENV.fetch('CHATWOOT_BRIDGE_BASE_URL', 'https://patrahq.com').to_s.chomp('/')
  end

  def account_id
    @account_id ||= ENV.fetch('CHATWOOT_BRIDGE_ACCOUNT_ID', '2').to_i
  end
end
