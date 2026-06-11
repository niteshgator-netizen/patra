# PROPOSED MIGRATION - NOT WIRED IN. MONEY-FLOWS RUN 3 (June 10, 2026).
#
# Everything in Run 3 works WITHOUT this migration: the orchestrator reads
# reply_preferences columns when they exist, then falls back to
# account.custom_attributes['<key>'], then to the operator-confirmed defaults
# (generosity_setting helper). Launch default = unconfigured = every freeplay/
# bonus/referral ask escalates to Telegram with the full case.
#
# Run it only to make the generosity settings first-class columns for the
# settings UI. Copy into db/migrate/ with a fresh timestamp to apply.

class AddGenerositySettingsToReplyPreferences < ActiveRecord::Migration[7.0]
  def change
    add_column :reply_preferences, :freeplay_amount, :decimal, precision: 10, scale: 2
    add_column :reply_preferences, :freeplay_daily_limit_per_player, :integer
    add_column :reply_preferences, :bonus_percent, :decimal, precision: 5, scale: 2
    add_column :reply_preferences, :first_deposit_bonus_percent, :decimal, precision: 5, scale: 2
    add_column :reply_preferences, :bonus_min_deposit, :decimal, precision: 10, scale: 2
    add_column :reply_preferences, :signup_bonus_amount, :decimal, precision: 10, scale: 2
    add_column :reply_preferences, :referral_reward_mode, :string
    add_column :reply_preferences, :referral_percent, :decimal, precision: 5, scale: 2
    add_column :reply_preferences, :referral_fixed_amount, :decimal, precision: 10, scale: 2
    add_column :reply_preferences, :referral_min_deposit, :decimal, precision: 10, scale: 2
  end
end
