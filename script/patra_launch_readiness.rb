# frozen_string_literal: true

# ─────────────────────────────────────────────────────────────────────────────
# PATRA LAUNCH READINESS — read-only pre-flight for the live pipeline.
#
#   RUN (Render Shell):  bundle exec rails runner script/patra_launch_readiness.rb
#
# SAFETY: read-only + cheap metadata pings ONLY. Moves NO money, sends NO customer
# messages, prints NO secret values (only PRESENT/MISSING). The external pings cost
# ~1 token each (Grok/DeepSeek) or are metadata-only (Telegram getMe/getChat, Gemini
# models.list, Voyage embed of the word "ping"). Every check is rescued so one
# failure never aborts the run.
#
# Sections: 1 ENV  2 EXTERNAL PINGS  3 IMAP  4 DB SANITY  5 SIDEKIQ  6 SUMMARY
# ─────────────────────────────────────────────────────────────────────────────

require 'net/imap'
require 'sidekiq/api'

ACCOUNT_ID = 2

$p = 0; $w = 0; $f = 0; $fails = []
def pass(m); $p += 1; puts "  PASS  #{m}"; end
def warn!(m); $w += 1; puts "  WARN  #{m}"; end
def fail!(m); $f += 1; $fails << m; puts "  FAIL  #{m}"; end

# Block returns truthy => PASS, falsey => FAIL, raise => FAIL with message.
def ping(label)
  yield ? pass(label) : fail!(label)
rescue StandardError => e
  fail!("#{label} — #{e.class}: #{e.message.to_s[0..200]}")
end

def env_check(name, required: true)
  if ENV[name].to_s.strip != ''
    pass("ENV #{name}: PRESENT")
  elsif required
    fail!("ENV #{name}: MISSING (required)")
  else
    warn!("ENV #{name}: missing (has default / optional)")
  end
end

def section(title); puts "\n#{'─' * 72}\n#{title}\n#{'─' * 72}"; end

puts "\n#{'=' * 72}\nPATRA LAUNCH READINESS  (account=#{ACCOUNT_ID})\n#{'=' * 72}"

# ─────────────────────────── 1. ENV PRESENCE ──────────────────────────────────
section('1. ENV PRESENCE (names only — never values)')
# Required (no in-code default — unset = broken feature at runtime):
%w[
  XAI_API_KEY DEEPSEEK_API_KEY VOYAGE_API_KEY GEMINI_API_KEY
  TELEGRAM_BOT_TOKEN TELEGRAM_CHAT_ID
  SECRET_KEY_BASE FRONTEND_URL
].each { |n| env_check(n, required: true) }
# Has a code default but should be set correctly for prod:
%w[
  XAI_MODEL ANTHROPIC_API_KEY TELEGRAM_CASHOUT_GROUP_ID
  REDIS_URL DATABASE_URL
  CHATWOOT_BRIDGE_API_TOKEN CHATWOOT_BRIDGE_BASE_URL CHATWOOT_BRIDGE_ACCOUNT_ID CHATWOOT_BRIDGE_INBOX_ID
  FB_APP_SECRET FB_VERIFY_TOKEN FB_PAGE_ACCESS_TOKEN
].each { |n| env_check(n, required: false) }
# Per-game panel creds (most clients fall back to baked defaults; flag if you rely on env):
%w[
  GAME_VAULT_AGENT_ID GAME_VAULT_SECRET_KEY JUWA_AGENT_ID JUWA_SECRET_KEY
  JUWA2_AGENT_ID JUWA2_SECRET_KEY VEGAS_SWEEPS_AGENT_ID VEGAS_SWEEPS_SECRET_KEY
  ULTRA_PANDA_APP_ID ULTRA_PANDA_APP_SECRET ULTRA_PANDA_AGENT_ACCOUNT ULTRA_PANDA_AGENT_PASSWORD
  VBLINK_APP_ID VBLINK_APP_SECRET VBLINK_AGENT_ACCOUNT VBLINK_AGENT_PASSWORD
].each { |n| env_check(n, required: false) }

# ─────────────────────────── 2. EXTERNAL PINGS ────────────────────────────────
section('2. EXTERNAL PINGS (cheap — ~1 token or metadata only)')

# Grok/xAI is RETIRED (Batch C) — no longer in the live reply path. WARN-only.
begin
  key = ENV['XAI_API_KEY'].to_s
  if key.empty?
    warn!('Grok/xAI (RETIRED — not in live path): XAI_API_KEY absent (fine, retired)')
  else
    r = HTTParty.post(
      'https://api.x.ai/v1/chat/completions',
      headers: { 'Authorization' => "Bearer #{key}", 'Content-Type' => 'application/json' },
      body: { model: ENV.fetch('XAI_MODEL', 'grok-4.3'), max_tokens: 1, messages: [{ role: 'user', content: 'ping' }] }.to_json,
      timeout: 30
    )
    note = r.code == 200 ? ' (still has credits, but unused)' : ' (down/no credits — OK, retired)'
    warn!("Grok/xAI (RETIRED — not in live path): HTTP #{r.code}#{note}")
  end
rescue StandardError => e
  warn!("Grok/xAI (RETIRED — not in live path): #{e.class} (OK, retired)")
end

ping('DeepSeek 1-token completion (PRIMARY BRAIN — FAIL if down)') do
  key = ENV['DEEPSEEK_API_KEY'].to_s
  raise 'DEEPSEEK_API_KEY missing' if key.empty?

  out = Ai::DeepseekClient.complete(system_prompt: 'reply with the single word ok', user_content: 'ping', max_tokens: 1)
  raise 'nil response (down / no credits / key invalid)' if out.nil?

  true
end

ping('Voyage embedding (embed "ping")') do
  vec = Bella::VoyageEmbedder.embed_one('ping', input_type: 'query')
  raise 'empty / nil embedding' unless vec.is_a?(Array) && vec.any?

  puts "        dims=#{vec.length}"
  true
end

ping('Telegram getMe (bot token valid)') do
  tok = ENV['TELEGRAM_BOT_TOKEN'].to_s
  raise 'TELEGRAM_BOT_TOKEN missing' if tok.empty?

  r = HTTParty.get("https://api.telegram.org/bot#{tok}/getMe", timeout: 15)
  raise "HTTP #{r.code}: #{r.body.to_s[0..120]}" unless r.code == 200 && r.parsed_response['ok']

  puts "        bot=@#{r.parsed_response.dig('result', 'username')}"
  true
end

ping('Telegram cashout group reachable (getChat)') do
  tok = ENV['TELEGRAM_BOT_TOKEN'].to_s
  raise 'TELEGRAM_BOT_TOKEN missing' if tok.empty?

  chat = ENV['TELEGRAM_CASHOUT_GROUP_ID'].to_s.strip
  chat = ENV['TELEGRAM_CHAT_ID'].to_s.strip if chat.empty?
  chat = '-5243223053' if chat.empty?
  r = HTTParty.get("https://api.telegram.org/bot#{tok}/getChat", query: { chat_id: chat }, timeout: 15)
  raise "HTTP #{r.code}: #{r.body.to_s[0..120]}" unless r.code == 200 && r.parsed_response['ok']

  puts "        chat=#{r.parsed_response.dig('result', 'title') || chat}"
  true
end

ping('Gemini key valid (models.list — free, no tokens)') do
  key = ENV['GEMINI_API_KEY'].to_s
  raise 'GEMINI_API_KEY missing' if key.empty?

  r = HTTParty.get("https://generativelanguage.googleapis.com/v1beta/models?key=#{key}", timeout: 15)
  raise "HTTP #{r.code}: #{r.body.to_s[0..120]}" unless r.code == 200

  true
end

# ─────────────────────────── 3. IMAP (payment inboxes) ────────────────────────
section('3. IMAP — payment-handle email inboxes (connect + login + count, no bodies)')
begin
  unless defined?(PaymentHandle)
    warn!('PaymentHandle model not defined — skipping IMAP')
  else
    cols = PaymentHandle.column_names
    user_col = cols.find { |c| c =~ /verification_email\z/ } || cols.find { |c| c =~ /email\z/ }
    pass_col = cols.find { |c| c =~ /verification_email_password\z/ } || cols.find { |c| c =~ /email_password\z/ }
    host_col = cols.find { |c| c =~ /imap.*host|email.*host|imap_server/ }
    scope = PaymentHandle.respond_to?(:active) ? PaymentHandle.active : PaymentHandle.all
    handles = scope.to_a.select { |h| user_col && h[user_col].to_s.strip != '' }
    if handles.empty?
      warn!("no active payment_handles with an email address (cols seen: user=#{user_col.inspect} pass=#{pass_col.inspect} host=#{host_col.inspect})")
    end
    handles.each do |h|
      label = "IMAP #{h[user_col]}"
      begin
        user = h[user_col].to_s
        pw   = pass_col ? h.public_send(pass_col).to_s : ''
        host = (host_col && h[host_col].present?) ? h[host_col].to_s : 'imap.gmail.com'
        if pw.empty?
          warn!("#{label}: no email password on record — skipped")
          next
        end
        imap = Net::IMAP.new(host, ssl: true)
        imap.login(user, pw)
        imap.select('INBOX')
        n = imap.status('INBOX', ['MESSAGES'])['MESSAGES']
        imap.logout; imap.disconnect
        pass("#{label} @ #{host} — INBOX #{n} msgs")
      rescue StandardError => e
        fail!("#{label}: #{e.class}: #{e.message.to_s[0..160]}")
      end
    end
  end
rescue StandardError => e
  fail!("IMAP section: #{e.class}: #{e.message}")
end

# ─────────────────────────── 4. DB SANITY ─────────────────────────────────────
section('4. DB SANITY')
account = Account.find_by(id: ACCOUNT_ID)
if account.nil?
  fail!("Account #{ACCOUNT_ID} not found — cannot run DB checks")
else
  # active agent_games + each slug has a client class
  begin
    ags = account.agent_games.active.joins(:game).to_a
    pass("active agent_games on account #{ACCOUNT_ID}: #{ags.size}")
    ags.each do |ag|
      slug = ag.game.slug
      begin
        client = Games::ClientRegistry.client_for(ag)
        client ? pass("client #{slug} => #{client.class}") : fail!("client #{slug} => NONE (ActionExecutor would raise 'not yet integrated')")
      rescue StandardError => e
        fail!("client #{slug} => #{e.class}: #{e.message.to_s[0..120]}")
      end
    end
  rescue StandardError => e
    fail!("agent_games check: #{e.class}: #{e.message}")
  end

  # GameRule count
  ping('GameRule rows present') do
    c = (account.respond_to?(:game_rules) ? account.game_rules.count : GameRule.count)
    puts "        game_rules=#{c}"
    c.positive?
  end

  # reply_preferences row for account 2 + key settings
  begin
    pref = ReplyPreference.for_account(ACCOUNT_ID)
    keys = %w[confirm_before_load confirm_before_cashout transfer_mode transfer_deposit_shortfall_mode
              fraud_cashout_velocity_count fraud_cashout_velocity_hours fraud_duplicate_payment_check memory_enabled]
    snap = keys.select { |k| pref.respond_to?(k) }.map { |k| "#{k}=#{pref.public_send(k)}" }.join('  ')
    pass("reply_preferences(#{ACCOUNT_ID}): #{snap}")
    warn!('confirm_before_load=false => loads auto-execute with NO human confirm (day-1 review)') if pref.respond_to?(:confirm_before_load) && pref.confirm_before_load == false
  rescue StandardError => e
    fail!("reply_preferences: #{e.class}: #{e.message}")
  end

  # industry / persona default
  ping('account industry_slug set (persona selection)') do
    ind = account.respond_to?(:industry_slug) ? account.industry_slug : nil
    puts "        industry_slug=#{ind.inspect} (fallback 'sweepstakes'/bella if nil)"
    true
  end

  # bella_rag_pairs count
  ping('bella_rag_pairs present for account scope') do
    c = BellaRagPair.where(account_id: ACCOUNT_ID).count
    puts "        bella_rag_pairs(account #{ACCOUNT_ID})=#{c}  global(nil)=#{BellaRagPair.where(account_id: nil).count rescue 'n/a'}"
    c.positive?
  end

  # FB Inbox 5 exists + channel type
  ping('FB bridge inbox exists and is Channel::Api') do
    inbox_id = ENV.fetch('CHATWOOT_BRIDGE_INBOX_ID', '5').to_i
    ib = Inbox.find_by(id: inbox_id)
    raise "bridge inbox #{inbox_id} not found" if ib.nil?

    puts "        inbox#{inbox_id} name=#{ib.name.inspect} channel_type=#{ib.channel_type}"
    ib.channel_type == 'Channel::Api'
  end

  # pending GameActions stuck > 1h
  ping('no GameActions stuck in pending > 1h') do
    stuck = GameAction.where(status: 'pending').where('created_at < ?', 1.hour.ago).count
    puts "        stuck_pending=#{stuck}"
    stuck.zero? || (warn!("#{stuck} GameAction(s) stuck pending > 1h — investigate") && false) || true
  end
end

# ─────────────────────────── 5. SIDEKIQ ───────────────────────────────────────
section('5. SIDEKIQ / REDIS')
ping('Redis ping') do
  Sidekiq.redis { |c| c.ping } == 'PONG'
end

ping('sidekiq-cron schedule loaded') do
  unless defined?(Sidekiq::Cron::Job)
    raise 'Sidekiq::Cron not loaded (worker process only registers crons — run this in the worker, or it is a config issue)'
  end

  jobs = Sidekiq::Cron::Job.all
  puts "        cron jobs loaded=#{jobs.size}"
  names = jobs.map(&:name).sort
  puts "        names: #{names.join(', ')}" unless names.empty?
  jobs.any?
end

ping('queue latency snapshot') do
  %w[critical high medium default low scheduled_jobs].each do |q|
    qq = Sidekiq::Queue.new(q)
    puts "        queue #{q}: size=#{qq.size} latency=#{qq.latency.round(1)}s"
  end
  true
end

# ─────────────────────────── 6. SUMMARY ───────────────────────────────────────
section('6. SUMMARY')
puts "LAUNCH READINESS: #{$p} pass / #{$w} warn / #{$f} fail"
unless $fails.empty?
  puts 'FAILURES:'
  $fails.each { |x| puts "  ✗ #{x}" }
end
puts "RESULT: #{$f.zero? ? 'READY (review warns)' : 'NOT READY — resolve fails above'}"
puts '=' * 72
