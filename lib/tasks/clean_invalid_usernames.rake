# frozen_string_literal: true

desc 'Remove game_username custom attribute when value is denylisted. Optional ACCOUNT_ID=2'
task clean_invalid_usernames: :environment do
  relation = Contact.all
  relation = relation.where(account_id: ENV['ACCOUNT_ID'].to_i) if ENV['ACCOUNT_ID'].present?

  cleared = Ai::ReplyService.remove_denylisted_game_username_from_contacts!(relation: relation)
  puts "Removed junk game_username from #{cleared} contact(s)."
end
