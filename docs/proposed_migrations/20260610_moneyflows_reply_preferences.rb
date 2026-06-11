# PROPOSED MIGRATION - NOT WIRED IN. MONEY-FLOWS RUN 1 (June 10, 2026).
#
# Everything in this run works WITHOUT this migration: the orchestrator reads
# reply_preferences columns when they exist, then falls back to
# account.custom_attributes['<key>'], then to the operator-confirmed defaults
# (transfer_mode 'deposit_only', cashout_overmax_mode 'cash_whole',
# auto_load_threshold 200 dollars).
#
# Run it only if the operator wants these settings as first-class columns
# (e.g. to expose them in the settings UI). To apply: copy into db/migrate/
# with a fresh timestamp and run on Render. The custom_attributes fallback
# keeps working either way.
#
# NOTE: changing the transfer_mode column DEFAULT does not change existing
# rows - account 2 keeps its current explicit value ('whole' unless changed).
# The dollar auto_load_threshold is intentionally distinct from the 0-100
# email-confidence 'auto_load_threshold' inside payment_scoring_config.

class AddMoneyflowSettingsToReplyPreferences < ActiveRecord::Migration[7.0]
  def up
    change_column_default :reply_preferences, :transfer_mode, 'deposit_only'
    add_column :reply_preferences, :cashout_overmax_mode, :string, default: 'cash_whole'
    add_column :reply_preferences, :auto_load_threshold, :decimal, precision: 10, scale: 2, default: 200.0
  end

  def down
    change_column_default :reply_preferences, :transfer_mode, 'whole'
    remove_column :reply_preferences, :cashout_overmax_mode
    remove_column :reply_preferences, :auto_load_threshold
  end
end
