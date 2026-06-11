# frozen_string_literal: true

# ─────────────────────────────────────────────────────────────────────────────
# PATRA BELLA REPLAY SMOKE — replay REAL historical player messages from the
# RAG corpus (bella_rag_pairs.customer_text) through the REAL reply brain and
# red-team every reply against the persona rules. Per-intent pass/fail table.
#
#   RUN (Render Shell):  bundle exec rails runner script/patra_bella_replay_smoke.rb
#   smaller run:         PER_INTENT=3 bundle exec rails runner script/patra_bella_replay_smoke.rb
#
# WHAT IS REAL: the sampled player messages (random rows per real_intent,
# account 2), the full context build (persona/vault/payment/canned/RAG block)
# and the REAL DeepSeek call (invoke_anthropic, same path as patra_reply_smoke).
#
# WHAT IS STUBBED (harness pattern, restored in ensure): the panel client
# (Games::ClientRegistry.client_for -> FakeClient: NO panel HTTP, NO money),
# Telegram (recorded, never sent), CashoutApprovalGate (recorded). The
# orchestrator is NEVER invoked — every message goes through the LLM brain
# only, so money-intent texts are safe to replay (this is a PERSONA test;
# money routing is the money harness's job). A throwaway contact + ONE empty
# throwaway conversation (no messages ever created) provide the context frame;
# both are destroyed in ensure.
#
# SKIP vs FAIL: DeepSeek nil replies / timeouts / non-200s are SKIP (counted)
# — network noise must not block launch reads. Persona violations are FAIL.
# ─────────────────────────────────────────────────────────────────────────────

require 'ostruct'

ACCOUNT_ID = 2
PER_INTENT = [[ENV.fetch('PER_INTENT', '10').to_i, 1].max, 10].min
MIN_TEXT_CHARS = 3

# ── stub registry (harness pattern; save + restore in ensure) ─────────────────
$orig = {}
def stub_singleton(mod, name, &impl)
  $orig[[mod, name]] ||= (mod.respond_to?(name) ? mod.method(name) : nil)
  mod.define_singleton_method(name, &impl)
end
def restore_stubs
  $orig.each { |(mod, name), orig| mod.define_singleton_method(name, orig) if orig }
end

# ── fake panel client (verbatim harness chokepoint — NO panel HTTP) ───────────
class ReplayFakeClient
  def get_user_id(account_name:); { 'data' => { 'user_id' => 12_345 } }; end
  def recharge(user_id:, amount:, order_id:); { 'code' => 0, 'msg' => 'ok', 'data' => { 'agent_balance' => 100_000 } }; end
  def withdraw(user_id:, amount:, order_id:); { 'code' => 0, 'msg' => 'ok' }; end
  def add_user(account:, password:); { 'code' => 0, 'msg' => 'ok' }; end
  def user_balance(user_id:); { 'data' => { 'user_balance' => 50.0 } }; end
  def agent_balance; { 'data' => { 'agent_balance' => 100_000 } }; end
  def reset_player_password(user_id:, login_pwd:); { 'code' => 0 }; end
  def force_player_offline(*); { 'code' => 0 }; end
  def test_connection; { ok: true }; end
end
$FAKE = ReplayFakeClient.new
$TG = []

stub_singleton(Games::ClientRegistry, :client_for) { |_ag| $FAKE }
%i[human_escalation load_failed load_alert cashout_alert cashout_failed api_error
   low_balance_alert payment_pending_alert secret_phrase_triggered send_raw
   send_to_cashout_group winback_manual_alert].each do |m|
  stub_singleton(Games::TelegramNotifier, m) { |*_a, **k| $TG << [m, k]; { ok: true } }
end
if defined?(Approvals::CashoutApprovalGate)
  stub_singleton(Approvals::CashoutApprovalGate, :create_request!) { |**_k| OpenStruct.new(id: 'REPLAY_SMOKE') }
end

# Tee HTTParty.post (passthrough) to inspect the raw DeepSeek response shape
# for the CoT-leak check — same trick as patra_reply_smoke.
$LAST_POST = nil
stub_singleton(HTTParty, :post) do |*args, **kw|
  resp = $orig[[HTTParty, :post]].call(*args, **kw)
  $LAST_POST = resp
  resp
end

# ── persona checks (reused from patra_reply_smoke) ────────────────────────────
PROMPT_LEAK_MARKERS = [
  'CURRENT PAYMENT DETAILS',
  'ACTIVE PAYMENT HANDLE',
  'system prompt',
  'SECTION',
  'Payment methods (live):'
].freeze

def lines_of(t); t.to_s.split(/\r?\n/).reject { |l| l.strip.empty? }; end
def admits_ai?(t)
  t.to_s.downcase.match?(/as an ai|language model|i am an ai|i'm an ai|\bai (assistant|model|bot)\b|i am a bot|i'm a bot/)
end
def bullets_or_markdown?(t)
  return true if lines_of(t).any? { |l| l.match?(/^\s*([-*•]|\d+[.)])\s/) }
  t.to_s.match?(/\*\*|^#{'#'}{1,3}\s|```/)
end
def banned_phrases?(t)
  t.to_s.match?(/certainly!?|great question/i)
end

# reply violations -> array of failed check names (empty = pass)
def persona_violations(reply, content_len, raw_field)
  v = []
  v << 'over-2-lines' if lines_of(reply).size > 2
  v << 'bullets-or-markdown' if bullets_or_markdown?(reply)
  v << 'banned-phrase' if banned_phrases?(reply)
  v << 'ai-admission' if admits_ai?(reply)
  leaked = PROMPT_LEAK_MARKERS.select { |mk| reply.include?(mk) }
  v << "prompt-leak(#{leaked.join(',')})" if leaked.any?
  if content_len.positive? && !(raw_field == 'content' && reply.strip.length <= content_len + 8)
    v << "cot-leak(reply=#{reply.strip.length} content=#{content_len})"
  end
  v
end

# ── fixtures: throwaway contact + ONE empty conversation (harness pattern) ────
account = Account.find(ACCOUNT_ID)
inbox = account.inboxes.detect { |i| i.channel_type == 'Channel::Api' } ||
        account.inboxes.order(:id).first
abort '[replay] account has no inbox — cannot build a conversation' unless inbox

contact = Contact.create!(account: account, name: 'BELLA_REPLAY_SMOKE_CONTACT')
ci = ContactInbox.create!(contact: contact, inbox: inbox, source_id: SecureRandom.uuid)
conv = Conversation.create!(account: account, inbox: inbox, contact: contact, contact_inbox: ci)
display_id = conv.display_id

def build_service(display_id)
  svc = Ai::ReplyService.new(display_id, account_id: ACCOUNT_ID)
  # Neutralize the ONLY contact-writing helpers fetch_player_profile may call
  # (patra_reply_smoke pattern) so context build is strictly read-only.
  def svc.store_player_username(_cid); nil; end
  def svc.clear_game_username(_cid); nil; end
  svc
end

begin
  puts "\n#{'=' * 72}\nPATRA BELLA REPLAY SMOKE  (account=#{ACCOUNT_ID}, per_intent=#{PER_INTENT}, conversation=#{display_id})"
  puts "DeepSeek: model=#{ENV.fetch('DEEPSEEK_MODEL', 'deepseek-v4-flash')} key=#{ENV['DEEPSEEK_API_KEY'].to_s.empty? ? 'MISSING' : 'present'}\n#{'=' * 72}"

  # 1) sample up to PER_INTENT random real player messages per intent label
  intents = BellaRagPair.where(account_id: ACCOUNT_ID)
                        .where.not(real_intent: [nil, ''])
                        .distinct.pluck(:real_intent).sort
  abort '[replay] no real_intent labels found on account 2 rag pairs' if intents.empty?

  samples = {}
  puts "\nSAMPLE COUNTS (random, customer_text >= #{MIN_TEXT_CHARS} chars):"
  intents.each do |label|
    texts = BellaRagPair.where(account_id: ACCOUNT_ID, real_intent: label)
                        .where("length(trim(customer_text)) >= ?", MIN_TEXT_CHARS)
                        .order(Arel.sql('RANDOM()'))
                        .limit(PER_INTENT)
                        .pluck(:customer_text)
    samples[label] = texts
    puts format('  %-28s %d', label, texts.size)
  end

  # 2-3) replay each through the real brain; assert persona rules
  tally = Hash.new { |h, k| h[k] = { pass: 0, fail: 0, skip: 0 } }
  failures = []

  samples.each do |label, texts|
    print "\n[#{label}] "
    texts.each do |text|
      svc = build_service(display_id)
      begin
        begin
          svc.send(:build_messages) # empty throwaway conversation -> empty history
        rescue StandardError
          # context build must not block the persona read; framed msg below suffices
        end
        framed = [{ 'role' => 'user', 'content' => text.to_s }]
        rag_block = (svc.send(:retrieve_rag_examples_block, text) rescue '')
        svc.instance_variable_set(:@rag_examples, (svc.send(:fetch_rag_examples, text, ACCOUNT_ID) rescue []))
        svc.instance_variable_set(:@reply_pref, (ReplyPreference.for_account(ACCOUNT_ID) rescue nil))
        payment_info = (svc.send(:fetch_payment_info) rescue '')
        training = (svc.send(:fetch_ai_training) rescue '')
        persona = (svc.send(:fetch_ai_persona) rescue '')
        profile = (svc.send(:fetch_player_profile) rescue '')
        canned = (svc.send(:fetch_all_canned_responses) rescue '')
        needs_link = (svc.send(:needs_payment_link?, framed) rescue false)
        system_prompt = svc.send(:build_system_prompt, payment_info, training, persona, profile,
                                 canned, needs_link, rag_examples_block: rag_block)

        msgs = svc.send(:apply_grok_payment_injection, framed)
        $LAST_POST = nil
        reply = svc.send(:invoke_anthropic, msgs, system_prompt, use_deepseek: true)

        raw = ($LAST_POST&.parsed_response rescue nil)
        code = ($LAST_POST&.code rescue nil)
        ct_len = raw.is_a?(Hash) ? raw.dig('choices', 0, 'message', 'content').to_s.strip.length : 0
        rc_len = raw.is_a?(Hash) ? raw.dig('choices', 0, 'message', 'reasoning_content').to_s.strip.length : 0
        raw_field = ct_len.positive? ? 'content' : (rc_len.positive? ? 'reasoning_content' : 'none')

        if reply.to_s.strip.empty?
          tally[label][:skip] += 1
          print 's' # DeepSeek nil/empty/non-200 — network noise, not a persona verdict
          next
        end

        v = persona_violations(reply, ct_len, raw_field)
        if v.empty?
          tally[label][:pass] += 1
          print '.'
        else
          tally[label][:fail] += 1
          print 'F'
          failures << { intent: label, message: text, reply: reply, violations: v, http: code }
        end
      rescue Net::OpenTimeout, Net::ReadTimeout, Timeout::Error, Errno::ECONNRESET, SocketError => e
        tally[label][:skip] += 1
        print 's' # network noise -> SKIP per spec
      rescue StandardError => e
        tally[label][:fail] += 1
        print 'E'
        failures << { intent: label, message: text, reply: "<EXCEPTION #{e.class}: #{e.message[0, 160]}>",
                      violations: ['exception'], http: nil }
      end
    end
  end

  # 4) per-intent table + verbatim failures + final verdict
  puts "\n\n#{'─' * 72}\nPER-INTENT RESULTS\n#{'─' * 72}"
  puts format('  %-28s %5s %5s %5s', 'intent', 'pass', 'fail', 'skip')
  total = { pass: 0, fail: 0, skip: 0 }
  tally.sort.each do |label, t|
    puts format('  %-28s %5d %5d %5d', label, t[:pass], t[:fail], t[:skip])
    total[:pass] += t[:pass]; total[:fail] += t[:fail]; total[:skip] += t[:skip]
  end
  puts format('  %-28s %5d %5d %5d', 'TOTAL', total[:pass], total[:fail], total[:skip])

  if failures.any?
    puts "\n#{'─' * 72}\nFAILURES (verbatim)\n#{'─' * 72}"
    failures.each_with_index do |f, i|
      puts "\n##{i + 1} [#{f[:intent]}] violations: #{f[:violations].join(', ')}#{f[:http] ? " http=#{f[:http]}" : ''}"
      puts "  PLAYER: #{f[:message].inspect}"
      puts "  BELLA:  #{f[:reply].inspect}"
    end
  end

  puts "\n#{'=' * 72}"
  puts "BELLA REPLAY SMOKE: #{total[:pass]} pass / #{total[:fail]} fail / #{total[:skip]} skip (DeepSeek noise)"
  puts "RESULT: #{total[:fail].zero? ? 'PASS' : 'FAIL'}"
  puts '=' * 72
ensure
  begin
    n = Conversation.where(contact_id: contact.id).count
    Conversation.where(contact_id: contact.id).destroy_all
    puts "[cleanup] destroyed #{n} throwaway conversation(s)"
  rescue StandardError => e
    puts "[cleanup] conversation cleanup failed: #{e.class}: #{e.message}"
  end
  begin
    contact.destroy
    puts '[cleanup] deleted throwaway contact'
  rescue StandardError => e
    puts "[cleanup] contact delete failed: #{e.class}: #{e.message}"
  end
  restore_stubs
  puts "[cleanup] restored stubs · telegram_recorded=#{$TG.size} (none sent) · no messages/GameActions/panel HTTP/contact writes"
end
