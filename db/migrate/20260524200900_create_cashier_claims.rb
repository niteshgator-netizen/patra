# frozen_string_literal: true

class CreateCashierClaims < ActiveRecord::Migration[7.1]
  def change
    create_table :cashier_claims do |t|
      t.references :account, null: false, foreign_key: true, index: true
      t.references :conversation, null: false, foreign_key: true, index: true
      t.references :contact, null: false, foreign_key: true, index: true
      t.string :action_type, null: false
      t.decimal :amount, precision: 12, scale: 2
      t.string :game_slug
      t.string :status, null: false, default: 'pending'
      t.references :claimed_by_user, foreign_key: { to_table: :users }
      t.datetime :claimed_at
      t.datetime :completed_at
      t.datetime :expires_at
      t.timestamps
    end

    add_index :cashier_claims, [:account_id, :status]
    add_index :cashier_claims, :expires_at
  end
end
