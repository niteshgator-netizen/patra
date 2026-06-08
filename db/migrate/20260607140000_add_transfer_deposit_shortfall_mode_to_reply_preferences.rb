class AddTransferDepositShortfallModeToReplyPreferences < ActiveRecord::Migration[7.0]
  def change
    add_column :reply_preferences, :transfer_deposit_shortfall_mode, :string, default: 'transfer_available'
  end
end
