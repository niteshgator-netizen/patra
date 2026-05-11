# frozen_string_literal: true

# One-time data fix: strip denylisted junk from contacts.game_username (custom_attributes).
# Same logic as `rake clean_invalid_usernames`; safe to re-run (no-op when clean).
class CleanDenylistedGameUsernamesData < ActiveRecord::Migration[7.0]
  def up
    say_with_time 'Removing denylisted game_username values from contacts' do
      Ai::ReplyService.remove_denylisted_game_username_from_contacts!
    end
  end

  def down
    # Irreversible: cleared values are not recoverable.
  end
end
