class AddReferralSettingsToReplyPreferences < ActiveRecord::Migration[7.0]
  def change
    add_column :reply_preferences, :referral_enabled, :boolean, default: false
    add_column :reply_preferences, :referral_bonus_referrer, :decimal, precision: 10, scale: 2, default: 5.00
    add_column :reply_preferences, :referral_bonus_new_player, :decimal, precision: 10, scale: 2, default: 5.00
    add_column :reply_preferences, :referral_bonus_type, :string, default: 'freeplay'
    add_column :reply_preferences, :referral_require_deposit, :boolean, default: true
    add_column :reply_preferences, :referral_tracking_method, :string, default: 'manual'
    add_column :reply_preferences, :referral_message_referrer, :text, default: 'thanks for the referral! {amount} loaded ✅'
    add_column :reply_preferences, :referral_message_new_player, :text, default: 'welcome! referred by {referrer_name}'
  end
end
