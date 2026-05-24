# frozen_string_literal: true

class CreateApprovalRequests < ActiveRecord::Migration[7.1]
  def change
    create_table :approval_requests do |t|
      t.references :account, null: false, foreign_key: true, index: true
      t.references :requesting_user, null: false, foreign_key: { to_table: :users }
      t.references :approving_user, foreign_key: { to_table: :users }
      t.string :action_type, null: false
      t.string :target_type
      t.bigint :target_id
      t.decimal :amount, precision: 12, scale: 2
      t.string :status, null: false, default: 'pending'
      t.jsonb :metadata, default: {}, null: false
      t.datetime :responded_at
      t.timestamps
    end

    add_index :approval_requests, [:account_id, :status]
    add_index :approval_requests, [:target_type, :target_id]
  end
end
