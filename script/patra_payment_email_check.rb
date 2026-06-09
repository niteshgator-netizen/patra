# frozen_string_literal: true

# ─────────────────────────────────────────────────────────────────────────────
# PATRA PAYMENT-EMAIL CHECK — read-only end-to-end probe of email payment verify.
# For each active payment_handle with a verification_email:
#   PART A  connect to the inbox + fetch recent emails (STRICTLY read-only)
#   PART B  run Payments::PaymentNotificationEmailParser on them, tally hits/misses
#   PART C  map a parsed result to the orchestrator's confirmed-payment gate shape
#
#   RUN (Render Shell):  bundle exec rails runner script/patra_payment_email_check.rb
#
# STRICTLY READ-ONLY: connects via Net::IMAP with EXAMINE (read-only mailbox select,
# server forbids STORE/EXPUNGE) and BODY.PEEK (does NOT set the \Seen flag). It does
# NOT delete, flag, mark-loaded, write any record, send anything, or move money.
# Each handle is wrapped in begin/rescue so one bad inbox never kills the run.
# Emails/sender names are redacted in output (going into chat).
# ─────────────────────────────────────────────────────────────────────────────

require 'net/imap'
require 'mail'

FETCH_COUNT = 20

def redact_email(e)
  s = e.to_s
  return '(none)' if s.strip.empty?
  user, dom = s.split('@', 2)
  "#{user.to_s[0, 2]}***@#{dom}"
end

def redact_name(n)
  parts = n.to_s.strip.split(/\s+/)
  return '(blank)' if parts.empty?
  parts.map { |p| p[0].to_s.upcase }.join('.') + '.'
end

def trunc(s, n = 54)
  s.to_s.gsub(/\s+/, ' ').strip[0, n]
end

PAY_PAT = Payments::PaymentNotificationEmailParser::PAYMENT_SUBJECT_PATTERN

def looks_like_payment?(mail)
  subj = mail.subject.to_s
  body = mail.body.to_s
  subj.match?(PAY_PAT) || body.match?(PAY_PAT) || (subj.match?(/\$\d/) && body.match?(/\$\d/))
rescue StandardError
  false
end

# Strictly read-only fetch: EXAMINE (read-only) + BODY.PEEK (no \Seen). Returns
# [Mail, ...] or raises (caller rescues). NEVER stores/deletes/flags.
def fetch_readonly(handle, count)
  host = handle.verification_email_host.to_s.presence || 'imap.gmail.com'
  port = handle.verification_email_port || 993
  ssl  = handle.verification_email_ssl != false

  imap = Net::IMAP.new(host, port: port, ssl: ssl)
  begin
    imap.login(handle.verification_email, handle.verification_email_password)
    imap.examine('INBOX') # READ-ONLY select — STORE/EXPUNGE rejected by the server
    seqs = imap.search(['ALL'])
    recent = seqs.last(count)
    return [] if recent.empty?

    fetched = imap.fetch(recent, 'BODY.PEEK[]') || [] # PEEK => \Seen unchanged
    fetched.map do |fd|
      raw = fd.attr['BODY[]']
      raw ? Mail.new(raw) : nil
    end.compact
  ensure
    begin; imap.logout; rescue StandardError; end
    begin; imap.disconnect; rescue StandardError; end
  end
end

line = '=' * 74
puts "#{line}\nPATRA PAYMENT-EMAIL CHECK (read-only)\n#{line}"

handles = PaymentHandle.where(status: 'active').to_a.select { |h| h.verification_email.to_s.present? }
puts "Active handles with a verification_email: #{handles.size}\n"

grand = { handles: 0, connected: 0, fetched: 0, looked: 0, parsed: 0 }
sample_parse = nil

handles.each do |handle|
  grand[:handles] += 1
  tag = "acct=#{handle.account_id} platform=#{handle.platform} inbox=#{redact_email(handle.verification_email)}"
  puts "\n#{'-' * 74}\n[handle ##{handle.id}] #{tag}"

  begin
    mails = fetch_readonly(handle, FETCH_COUNT)
    grand[:connected] += 1
    grand[:fetched] += mails.size
    puts "  PART A: ✓ CONNECTED — fetched #{mails.size} email(s)"

    looked = 0
    parsed = 0
    mails.each do |mail|
      next unless looks_like_payment?(mail)
      looked += 1
      subj = trunc(mail.subject)
      begin
        result = Payments::PaymentNotificationEmailParser.new(mail: mail, platform: handle.platform).parse
        if result && result[:amount].to_f.positive?
          parsed += 1
          sample_parse ||= { handle: handle, result: result, subject: subj }
          puts "    ✓ PARSE  $#{result[:amount]}  from #{redact_name(result[:sender_name])}  | subj: #{subj}"
        else
          puts "    ✗ MISS   (no match)                         | subj: #{subj}"
        end
      rescue StandardError => e
        puts "    ! PARSE-ERR #{e.class}: #{e.message[0, 60]}     | subj: #{subj}"
      end
    end
    grand[:looked] += looked
    grand[:parsed] += parsed
    pct = looked.zero? ? 0 : (parsed.to_f / looked * 100).round
    puts "  PART B TALLY: fetched #{mails.size} | looked-like-payment #{looked} | parsed-ok #{parsed} (#{pct}%)"
  rescue Net::IMAP::NoResponseError => e
    puts "  PART A: ✗ FAILED — AUTH/MAILBOX error: #{e.message[0, 90]}"
  rescue SocketError, Net::OpenTimeout, Errno::ECONNREFUSED, Errno::ETIMEDOUT => e
    puts "  PART A: ✗ FAILED — HOST/NETWORK error: #{e.class}: #{e.message[0, 80]}"
  rescue StandardError => e
    puts "  PART A: ✗ FAILED — #{e.class}: #{e.message[0, 90]}"
  end
end

# ── PART C — gate shape (no writes) ───────────────────────────────────────────
puts "\n#{line}\nPART C — confirmed-payment gate shape (no writes)\n#{line}"
if sample_parse
  r = sample_parse[:result]
  h = sample_parse[:handle]
  puts "Sample parsed email (handle ##{h.id}, #{h.platform}):"
  puts "  parser =>  amount=#{r[:amount]}  sender=#{redact_name(r[:sender_name])}  handle=#{r[:sender_handle]}  txn=#{r[:transaction_id]}  received=#{r[:email_received_at]}"
  puts "\nfind_matching_confirmed_payment expects a patra_finance_logs entry with:"
  puts "  status            ∈ {confirmed, completed, verified} OR includes 'verified' OR 'email verified'"
  puts "  flag_reason       blank"
  puts "  email_confirmed   == true  (when raw_status needs email confirmation)"
  puts "  amount            positive + within 0.01 of requested"
  puts "  recorded_at | image_received_at | transaction_time  within 30 min"
  puts "\nMapping parser-output -> finance-log fields the gate reads:"
  puts "  amount        => log['amount']                 ✓ (parser provides #{r[:amount]})"
  puts "  email_received_at => log['recorded_at']        ✓ (parser provides #{r[:email_received_at]})"
  puts "  platform      => log['platform']               (from handle = #{h.platform}, set at ingestion)"
  puts "  transaction_id=> log['transaction_id']/['id']  #{r[:transaction_id] ? '✓' : '— (none extracted)'}"
  puts "  status / email_confirmed                       set by ghost-ingestion / EmailConfirmationService, NOT the parser"
  puts "\nNOTE: the PARSER creates/feeds a finance log (ghost ingestion). The IMAP-confirm"
  puts "path (EmailConfirmationService -> ImapVerifier#verify, substring match) flips an"
  puts "existing screenshot log to status='Email Verified' + email_confirmed=true, which is"
  puts "what unlocks the gate. A parsed email alone is NOT yet gate-matchable until a log"
  puts "entry carries an acceptable status + email_confirmed + recorded_at."
else
  puts "No email parsed successfully — cannot show a sample gate mapping."
  puts "(If PART A connected but PART B parsed 0/looked>0, the parser patterns are likely"
  puts " stale vs the current email formats — that's the thing to fix before launch.)"
end

# ── summary ───────────────────────────────────────────────────────────────────
puts "\n#{line}"
puts "SUMMARY: handles=#{grand[:handles]} connected=#{grand[:connected]} " \
     "fetched=#{grand[:fetched]} looked=#{grand[:looked]} parsed=#{grand[:parsed]}"
overall_pct = grand[:looked].zero? ? 0 : (grand[:parsed].to_f / grand[:looked] * 100).round
puts "Overall parse rate (parsed/looked): #{overall_pct}%"
puts "HEALTHY = every handle CONNECTED + parse rate high. PROBLEM = any ✗ FAILED (auth/host)"
puts "or a low parse rate (stale patterns)."
puts line
