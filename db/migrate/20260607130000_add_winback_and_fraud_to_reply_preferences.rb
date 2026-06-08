class AddWinbackAndFraudToReplyPreferences < ActiveRecord::Migration[7.0]
  def change
    add_column :reply_preferences, :transfer_mode, :string, default: 'whole'
    add_column :reply_preferences, :winback_enabled, :boolean, default: false
    add_column :reply_preferences, :winback_dormant_days_vip, :integer, default: 3
    add_column :reply_preferences, :winback_dormant_days_regular, :integer, default: 14
    add_column :reply_preferences, :winback_dormant_days_new, :integer, default: 7
    add_column :reply_preferences, :fraud_cashout_velocity_count, :integer, default: 3
    add_column :reply_preferences, :fraud_cashout_velocity_hours, :integer, default: 24
    add_column :reply_preferences, :fraud_duplicate_payment_check, :boolean, default: true
  end
end
