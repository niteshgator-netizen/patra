# frozen_string_literal: true

class CreateBroadcasts < ActiveRecord::Migration[7.1]
  def change
    create_table :broadcasts do |t|
      t.references :account, null: false, foreign_key: true, index: true
      t.string :name, null: false
      t.string :channel, null: false
      t.text :content, null: false
      t.string :media_url
      t.jsonb :segment_filter, default: {}, null: false
      t.string :status, null: false, default: 'draft'
      t.datetime :scheduled_at
      t.integer :sent_count, default: 0, null: false
      t.integer :failed_count, default: 0, null: false
      t.references :created_by_user, foreign_key: { to_table: :users }
      t.timestamps
    end

    add_index :broadcasts, [:account_id, :status]
    add_index :broadcasts, [:account_id, :scheduled_at]
  end
end
