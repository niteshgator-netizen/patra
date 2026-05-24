# frozen_string_literal: true

class CreateBackupPages < ActiveRecord::Migration[7.1]
  def change
    create_table :backup_pages do |t|
      t.references :account, null: false, foreign_key: true, index: true
      t.string :platform, null: false
      t.string :page_id, null: false
      t.string :page_name
      t.text :access_token
      t.string :status, null: false, default: 'standby'
      t.integer :position, default: 0, null: false
      t.datetime :health_check_at
      t.jsonb :stats, default: {}, null: false
      t.timestamps
    end

    add_index :backup_pages, [:account_id, :status]
    add_index :backup_pages, [:account_id, :position]
  end
end
