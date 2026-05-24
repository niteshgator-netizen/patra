# frozen_string_literal: true

class CreateAuditLogs < ActiveRecord::Migration[7.1]
  def change
    create_table :audit_logs do |t|
      t.references :account, null: false, foreign_key: true, index: true
      t.references :user, foreign_key: true, index: true
      t.string :action, null: false
      t.string :target_type
      t.bigint :target_id
      t.jsonb :metadata, default: {}, null: false
      t.string :ip_address
      t.datetime :created_at, null: false
    end

    add_index :audit_logs, [:target_type, :target_id]
    add_index :audit_logs, [:account_id, :action]
    add_index :audit_logs, :created_at
  end
end
