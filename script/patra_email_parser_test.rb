# frozen_string_literal: true

# ─────────────────────────────────────────────────────────────────────────────
# PURE-RUBY test for Payments::PaymentNotificationEmailParser.
# Runs WITHOUT Rails (bundler is version-pinned here). Shims the few ActiveSupport
# helpers the parser uses + a fake Mail object, then loads the REAL parser file.
#
#   RUN:  ruby script/patra_email_parser_test.rb
#
# Proves: 3 real forwarded payment shapes parse with CLEAN names; 3 marketing
# emails return nil (false positives killed). READ-ONLY — no network, no writes.
# ─────────────────────────────────────────────────────────────────────────────

require 'time'

# ── minimal ActiveSupport shims (only what the parser touches) ───────────────
module ActiveSupport; class TimeWithZone; end; end unless defined?(ActiveSupport::TimeWithZone)

class Object
  def blank?; respond_to?(:empty?) ? !!empty? : !self; end
  def present?; !blank?; end
  def presence; present? ? self : nil; end
end
class NilClass; def blank?; true; end; end
class String;   def blank?; strip.empty?; end; end

# ── fake Mail message (duck-types what the parser reads) ─────────────────────
FakeMail = Struct.new(:subject, :body, :from, :message_id, :date)

# load the real parser
load File.join(__dir__, '..', 'app', 'services', 'payments', 'payment_notification_email_parser.rb')

CLEAN_NAME = /\A[A-Za-z][A-Za-z .'\-]*\z/ # no $, no digits, no dotted-garbage

def run(mail, platform)
  Payments::PaymentNotificationEmailParser.new(mail: mail, platform: platform).parse
rescue StandardError => e
  { _error: "#{e.class}: #{e.message}" }
end

now = Time.now

CASES = [
  { name: 'cashapp clean subject',
    platform: 'cashapp', expect: :parse, want_amount: 133.0, want_name: 'Charkesa Allen',
    mail: FakeMail.new(
      'FW: Charkesa Allen sent you $133.00 USD',
      "---------- Forwarded message ---------\nFrom: Cash App <cash@square.com>\n" \
      "Charkesa Allen sent you $133.00 for nothing.\nOpen Cash App: https://cash.app/account\n",
      ['forwarder@gmail.com'], '<1@cash>', now) },

  { name: 'chime "just sent you money" (no $ in subject)',
    platform: 'chime', expect: :parse, want_amount: 5.0, want_name: 'Kenia M',
    mail: FakeMail.new(
      'Kenia M. just sent you money 💸',
      "Chime\nKenia M. sent you $5.00 USD\nView the transfer in your app.\nchime.com\n",
      ['forwarder@gmail.com'], '<2@chime>', now) },

  { name: 'chime "You got $1.00" (no name in subject)',
    platform: 'chime', expect: :parse, want_amount: 1.0, want_name: 'Robert K',
    mail: FakeMail.new(
      'You got $1.00',
      "Chime\nYou got $1.00\nFrom Robert K.\nMember FDIC. chime.com\n",
      ['forwarder@gmail.com'], '<3@chime>', now) },

  { name: 'marketing: Google privacy ($752 in body)',
    platform: 'chime', expect: :nil,
    mail: FakeMail.new(
      'New privacy settings for Search services',
      "We updated your account settings. Your plan is worth $752 in value.\n" \
      "Manage settings at google.com\n",
      ['no-reply@google.com'], '<4@g>', now) },

  { name: 'marketing: "Last chance for a bigger bonus" ($36)',
    platform: 'cashapp', expect: :nil,
    mail: FakeMail.new(
      'Last chance for a bigger bonus',
      "Don't miss out! Claim your $36 bonus today before it expires.\noffers.example.com\n",
      ['promo@offers.example.com'], '<5@p>', now) },

  { name: 'marketing: "$20 seed bonus" savings promo',
    platform: 'chime', expect: :nil,
    mail: FakeMail.new(
      'Help kids grow their savings with a $20 seed bonus',
      "Open a savings account and we'll add a $20 seed bonus to get them started.\n" \
      "bank-promo.example.com\n",
      ['promo@bank-promo.example.com'], '<6@p>', now) }
].freeze

puts '=' * 74
puts 'PAYMENT-EMAIL PARSER TEST  (3 real shapes must parse clean · 3 marketing must die)'
puts '=' * 74

all_pass = true
CASES.each do |tc|
  res = run(tc[:mail], tc[:platform])
  ok = true
  detail = ''

  if tc[:expect] == :nil
    ok = res.nil?
    detail = res.nil? ? 'nil (rejected)' : "PARSED #{res.inspect} <-- should have been nil!"
  else
    if res.is_a?(Hash) && !res[:_error]
      amt   = res[:amount]
      name  = res[:sender_name].to_s
      clean = name.match?(CLEAN_NAME) && !name.empty?
      amt_ok  = tc[:want_amount].nil? || (amt.to_f - tc[:want_amount]).abs < 0.001
      name_ok = tc[:want_name].nil? ? clean : (name == tc[:want_name])
      ok = amt_ok && name_ok && clean
      detail = "amount=#{amt} name=#{name.inspect} clean=#{clean} (want amt=#{tc[:want_amount]} name=#{tc[:want_name].inspect})"
    else
      ok = false
      detail = "expected parse, got #{res.inspect}"
    end
  end

  all_pass &&= ok
  mark = tc[:expect] == :nil ? '✗→nil' : '✓→parse'
  puts "\n[#{ok ? 'PASS' : 'FAIL'}] (#{mark}) #{tc[:name]}"
  puts "       #{detail}"
end

puts "\n#{'=' * 74}"
puts all_pass ? 'RESULT: PASS — clean names on real payments, marketing rejected.' \
              : 'RESULT: FAIL — see lines above.'
puts '=' * 74
exit(all_pass ? 0 : 1)
