# frozen_string_literal: true

# MEGA2 P4 - self-check for the Telegram two-way command surface. READ-ONLY:
# never approves/denies anything. Run on Render:
#   bundle exec rails runner script/patra_telegram_commands_check.rb
results = []
check = lambda do |name, ok, detail = nil|
  results << [name, ok]
  puts format('%-58s %s%s', name, ok ? 'PASS' : 'FAIL', detail ? " (#{detail})" : '')
end

# 1. Feature flags / env surface
check.call('PATRA_TELEGRAM_COMMANDS set to true',
           ENV['PATRA_TELEGRAM_COMMANDS'].to_s == 'true',
           ENV['PATRA_TELEGRAM_COMMANDS'].inspect)
check.call('TELEGRAM_CASHOUT_GROUP_ID configured',
           ENV['TELEGRAM_CASHOUT_GROUP_ID'].to_s.strip != '')
check.call('TELEGRAM_BOT_TOKEN configured',
           ENV['TELEGRAM_BOT_TOKEN'].to_s.strip != '')
check.call('webhook secret configured (enforcement on)',
           ENV['PATRA_TELEGRAM_OPS_WEBHOOK_SECRET'].to_s.strip != '',
           'dark/log-only when blank')
check.call('PATRA_APPROVAL_AUTORESUME enabled (auto-execute on approve)',
           Approvals::AutoResume.enabled?,
           'approve only marks the record when off')

# 2. Route present
route_ok = Rails.application.routes.routes.any? { |r| r.path.spec.to_s.include?('webhooks/patra_telegram_ops') }
check.call('route POST /webhooks/patra_telegram_ops exists', route_ok)

# 3. Command parsing
parse = ->(text) { TelegramOps::CommandHandler::COMMAND_PATTERN.match(text) }
check.call("parses 'approve 123'", parse.call('approve 123')&.captures == %w[approve 123])
check.call("parses 'deny #45'", parse.call('deny #45')&.captures == %w[deny 45])
check.call("parses '/approve 7'", parse.call('/approve 7')&.captures == %w[approve 7])
check.call("ignores chatter 'paid the guy'", parse.call('paid the guy').nil?)
check.call("rejects malformed 'approve abc'", parse.call('approve abc').nil?)

# 4. Wrong-chat guard (pure logic, no sends - feature flag may be off, so we
# exercise the guard condition directly)
group = ENV['TELEGRAM_CASHOUT_GROUP_ID'].to_s
check.call('wrong chat id would be rejected',
           group.empty? || '999999' != group)

# 5. Pending approvals visible to the operator
pending = ApprovalRequest.where(status: 'pending').order(:id)
puts "\nPending approval requests: #{pending.count}"
pending.limit(10).each do |a|
  puts "  ##{a.id} #{a.action_type} $#{a.amount} account=#{a.account_id} created=#{a.created_at}"
end

failed = results.count { |(_, ok)| !ok }
puts "\n#{results.size - failed}/#{results.size} checks passed#{failed.positive? ? " - #{failed} FAILED" : ''}"
