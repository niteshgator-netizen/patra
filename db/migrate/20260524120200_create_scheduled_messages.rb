# frozen_string_literal: true

class CreateScheduledMessages < ActiveRecord::Migration[7.1]
  def change
    create_table :scheduled_messages do |t|
      t.references :account, null: false, foreign_key: true, index: true
      t.references :conversation, null: false, foreign_key: true, index: true
      t.text :content, null: false
      t.datetime :scheduled_at, null: false
      t.datetime :sent_at
      t.string :status, null: false, default: 'pending'
      t.references :created_by_user, null: false, foreign_key: { to_table: :users }
      t.timestamps
    end

    add_index :scheduled_messages, [:status, :scheduled_at]
  end
end
