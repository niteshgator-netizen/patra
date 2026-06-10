# frozen_string_literal: true

# ─────────────────────────────────────────────────────────────────────────────
# PATRA REPLY SMOKE — exercise the REAL reply brain end-to-end and PRINT the
# generated reply. ZERO messages created, ZERO sends, ZERO FB, ZERO money.
#
#   RUN (Render Shell):  bundle exec rails runner script/patra_reply_smoke.rb
#   pick a conversation:  CONV=<display_id> bundle exec rails runner script/patra_reply_smoke.rb
#
# WHAT IS REAL: the gates (intent detection), the 50-msg history fetch
# (build_messages), RAG retrieval + injection, persona/industry + vault + player
# memory prompt (build_system_prompt → fetch_player_profile), and the REAL
# DeepSeek call (the literal invoke_anthropic, Batch-C path). We tee HTTParty.post
# to read which raw field carried the text (content vs reasoning_content).
#
# WHAT IS STUBBED / SKIPPED (restored in ensure):
#   • Games::TelegramNotifier.*      → recorded as WOULD SEND, never sent
#   • Games::ClientRegistry.client_for → raises (no panel/money path may run)
#   • store_player_username / clear_game_username → no-op on the instance (the only
#     contact writes fetch_player_profile can do) so context build is READ-ONLY
#   • Players::ProfileService.sync!  → not called (it is a write; call() does it,
#     we don't call call())
#   • the orchestrator is NEVER invoked — money intents are gated out up front and
#     printed as "would-route: <intent>"; non-money messages go straight to the
#     LLM brain. So NO GameAction, NO orchestrator money handler ever runs.
# No persistence, no Message.create!, no contact mutation.
# ─────────────────────────────────────────────────────────────────────────────

ACCOUNT_ID = 2

# Intents that execute or record money (load/cashout/transfer/account/reset) — the
# script refuses to drive these (would touch the orchestrator's money handlers).
MONEY_INTENTS = %i[
  load load_freeplay load_bonus cashout redeem_partial_replay transfer_between_games
  request_account_creation request_multi_account_creation reset_password
  new_account_reissue payment_sent_confirmation payment_method_chosen username_provided
].freeze

SMOKES = [
  'yo what games you got',
  'how do i cash out',
  'load 20 on juwa',   # money path — must be SKIPPED, never executed
  'are you a bot'      # persona test — reply must NOT admit AI
].freeze

# ── stub registry (save + restore in ensure) ─────────────────────────────────
$orig = {}
def stub_singleton(mod, name, &impl)
  $orig[[mod, name]] ||= (mod.respond_to?(name) ? mod.method(name) : nil)
  mod.define_singleton_method(name, &impl)
end
def restore_stubs
  $orig.each { |(mod, name), orig| mod.define_singleton_method(name, orig) if orig }
end

$SENDS = []        # recorded "would send" (Telegram), never actually sent
$LAST_POST = nil   # tee of the most recent HTTParty.post response

# Telegram → record only.
%i[human_escalation load_failed load_alert cashout_alert cashout_failed api_error
   low_balance_alert payment_pending_alert secret_phrase_triggered send_raw
   send_to_cashout_group winback_manual_alert].each do |m|
  stub_singleton(Games::TelegramNotifier, m) { |*_a, **k| $SENDS << [:telegram, m, k]; { ok: true } }
end

# Any accidental money/panel path aborts loudly instead of moving a cent.
stub_singleton(Games::ClientRegistry, :client_for) { |_ag| raise 'SMOKE GUARD: panel client blocked (no money path allowed)' }

# Tee HTTParty.post (passthrough) so we can inspect the raw DeepSeek response shape.
stub_singleton(HTTParty, :post) do |*args, **kw|
  resp = $orig[[HTTParty, :post]].call(*args, **kw)
  $LAST_POST = resp
  resp
end

# ── helpers ──────────────────────────────────────────────────────────────────
$pass = 0; $fail = 0
def chk(cond, m); puts((cond ? '    PASS ' : '    FAIL ') + m); cond ? ($pass += 1) : ($fail += 1); end
def lines_of(t); t.to_s.split(/\r?\n/).reject { |l| l.strip.empty? }; end
def admits_ai?(t)
  t.to_s.downcase.match?(/as an ai|language model|i am an ai|i'm an ai|\bai (assistant|model|bot)\b|i am a bot|i'm a bot/)
end

def build_service(display_id)
  svc = Ai::ReplyService.new(display_id, account_id: ACCOUNT_ID)
  # Neutralize the ONLY contact-writing helpers fetch_player_profile may call,
  # so building the persona/vault/memory prompt is strictly read-only.
  def svc.store_player_username(_cid); nil; end
  def svc.clear_game_username(_cid); nil; end
  svc
end

# ── pick a real account-2 conversation ───────────────────────────────────────
account = Account.find(ACCOUNT_ID)
conv =
  if ENV['CONV'].to_s.strip != ''
    account.conversations.find_by(display_id: ENV['CONV'].to_i)
  else
    account.conversations.order(last_activity_at: :desc).first
  end
abort '[smoke] no conversation found for account 2 (set CONV=<display_id>)' unless conv
display_id = conv.display_id

begin
  puts "\n#{'=' * 72}\nPATRA REPLY SMOKE  (account=#{ACCOUNT_ID}, conversation display_id=#{display_id})\n#{'=' * 72}"
  puts "DeepSeek: model=#{ENV.fetch('DEEPSEEK_MODEL', 'deepseek-v4-flash')} max_tokens=#{ENV.fetch('DEEPSEEK_MAX_TOKENS', 800)} key=#{ENV['DEEPSEEK_API_KEY'].to_s.empty? ? 'MISSING' : 'present'}"

  SMOKES.each do |text|
    puts "\n#{'-' * 72}\nMESSAGE: #{text.inspect}"

    # 1) GATE — real intent detection
    det = begin
      Games::IntentDetector.detect(text)
    rescue StandardError => e
      puts "  intent detect error: #{e.class}: #{e.message}"; nil
    end
    intent = det.is_a?(Hash) ? det[:intent] : det
    puts "  intent=#{intent.inspect}"
    if MONEY_INTENTS.include?(intent)
      puts "  would-route: #{intent} (MONEY) — SKIPPED (script never executes orchestrator money handlers)"
      next
    end

    # 2) REAL context build (read-only; writes stubbed)
    svc = build_service(display_id)
    begin
      svc.send(:build_messages) # populates @conversation_history_for_llm (real 50-msg window) — read-only GET
    rescue StandardError => e
      puts "  build_messages error (continuing with smoke msg only): #{e.class}: #{e.message[0, 120]}"
    end
    history = Array(svc.send(:build_conversation_history)).map { |m| { 'role' => m['role'], 'content' => m['content'] } }
    framed = history + [{ 'role' => 'user', 'content' => text }]

    rag_block = (svc.send(:retrieve_rag_examples_block, text) rescue '')
    svc.instance_variable_set(:@rag_examples, (svc.send(:fetch_rag_examples, text, ACCOUNT_ID) rescue []))
    svc.instance_variable_set(:@reply_pref, (ReplyPreference.for_account(ACCOUNT_ID) rescue nil))
    payment_info = (svc.send(:fetch_payment_info) rescue '')
    training = (svc.send(:fetch_ai_training) rescue '')
    persona = (svc.send(:fetch_ai_persona) rescue '')
    profile = (svc.send(:fetch_player_profile) rescue '') # vault + player-memory lines (writes stubbed)
    canned = (svc.send(:fetch_all_canned_responses) rescue '')
    needs_link = (svc.send(:needs_payment_link?, framed) rescue false)
    system_prompt = svc.send(
      :build_system_prompt, payment_info, training, persona, profile, canned, needs_link, rag_examples_block: rag_block
    )

    puts "  context: history_msgs=#{history.size} sys_prompt_chars=#{system_prompt.length} " \
         "rag_examples=#{Array(svc.instance_variable_get(:@rag_examples)).size} " \
         "profile_has_memory=#{profile.to_s.include?('Who this player is')} " \
         "profile_has_vault=#{profile.to_s.include?('Player profile vault')}"

    # 3) REAL DeepSeek call (the literal invoke_anthropic — Batch-C path)
    msgs = svc.send(:apply_grok_payment_injection, framed)
    $LAST_POST = nil
    reply = begin
      svc.send(:invoke_anthropic, msgs, system_prompt, use_deepseek: true)
    rescue StandardError => e
      puts "  invoke_anthropic error: #{e.class}: #{e.message[0, 160]}"; nil
    end

    # Inspect the teed raw response to report which field carried the text.
    raw = ($LAST_POST&.parsed_response rescue nil)
    rc_len = raw.is_a?(Hash) ? raw.dig('choices', 0, 'message', 'reasoning_content').to_s.strip.length : 0
    ct_len = raw.is_a?(Hash) ? raw.dig('choices', 0, 'message', 'content').to_s.strip.length : 0
    field = rc_len.positive? ? 'reasoning_content' : (ct_len.positive? ? 'content' : 'none')
    code  = ($LAST_POST&.code rescue nil)

    puts "  routed=deepseek http=#{code.inspect} raw_field=#{field} (content_len=#{ct_len} reasoning_len=#{rc_len})"

    if reply.to_s.strip.empty?
      puts '  REPLY: <empty / nil>'
      chk(false, 'non-empty reply')
      next
    end

    ln = lines_of(reply)
    puts "  REPLY: #{reply.inspect}"
    puts "  lines=#{ln.size}"
    chk(!reply.strip.empty?, 'non-empty reply')
    chk(ln.size <= 2, "<= 2 lines (got #{ln.size})")
    chk(!admits_ai?(reply), 'no AI admission (no "as an AI" / "language model" / "im a bot")')
    puts "  WOULD SEND: #{reply.inspect}  (raw_field=#{field} content_len=#{ct_len} reasoning_len=#{rc_len})"
  end

  puts "\n#{'=' * 72}\nREPLY SMOKE: #{$pass} pass / #{$fail} fail"
  puts "RESULT: #{$fail.zero? ? 'PASS' : 'FAIL'}"
  puts '=' * 72
ensure
  restore_stubs
  puts "[cleanup] restored stubs · telegram_recorded=#{$SENDS.size} (none sent) · no messages/GameActions/contact writes"
end
