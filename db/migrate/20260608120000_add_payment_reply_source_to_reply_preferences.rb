class AddPaymentReplySourceToReplyPreferences < ActiveRecord::Migration[7.0]
  def change
    add_column :reply_preferences, :payment_reply_source, :string, default: 'canned'
  end
end
