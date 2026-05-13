class CreateNotificationChannels < ActiveRecord::Migration[7.1]
  def change
    create_table :notification_channels do |t|
      t.bigint :account_id, null: false
      t.string :channel_type, null: false # 'telegram', future: 'discord', 'whatsapp', etc.
      t.string :status, default: 'active', null: false # 'active', 'inactive', 'failed'
      t.jsonb :credentials, default: {} # encrypted bot_token, chat_id, etc.
      t.jsonb :event_filters, default: {} # which events to send {load: true, cashout: true, failures: true, escalations: true}
      t.string :last_test_status # 'success', 'failed'
      t.text :last_test_message
      t.datetime :last_test_at
      t.datetime :last_used_at
      t.integer :failure_count, default: 0
      t.datetime :last_failure_at
      t.timestamps
    end

    add_index :notification_channels, [:account_id, :channel_type], unique: true
  end
end
