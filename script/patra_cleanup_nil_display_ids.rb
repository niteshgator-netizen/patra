# frozen_string_literal: true

# patra-final 5a (G59): REPORT-ONLY. Lists conversations whose display_id is
# NULL — these are what made ActionCableBroadcastJob die (1,189 dead jobs).
# It does NOT delete or modify anything; Genius reads the output and decides.
#
# Run on Render:
#   bundle exec rails runner script/patra_cleanup_nil_display_ids.rb
#
# Success looks like: a count plus one line per affected conversation.

rows = Conversation.where(display_id: nil)
                   .order(:account_id, :id)
                   .pluck(:id, :account_id, :inbox_id, :contact_id, :created_at)

puts "Conversations with NULL display_id: #{rows.size}"

if rows.empty?
  puts 'Nothing to clean up.'
else
  puts format('%-12s %-10s %-9s %-10s %s', 'id', 'account', 'inbox', 'contact', 'created_at')
  rows.each do |id, account_id, inbox_id, contact_id, created_at|
    puts format('%-12s %-10s %-9s %-10s %s', id, account_id, inbox_id, contact_id, created_at)
  end
  puts ''
  puts 'Report only — no rows were changed. To repair instead of delete, each'
  puts 'conversation needs a display_id from its account sequence; decide with'
  puts 'the planning Claude before any mutation.'
end
