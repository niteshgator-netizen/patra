# frozen_string_literal: true

class CreateAccountingSyncs < ActiveRecord::Migration[7.1]
  def change
    create_table :accounting_syncs do |t|
      t.references :account, null: false, foreign_key: true, index: true
      t.string :provider, null: false
      t.jsonb :mapping, default: {}, null: false
      t.jsonb :last_export, default: {}, null: false
      t.string :status, null: false, default: 'pending'
      t.timestamps
    end

    add_index :accounting_syncs, [:account_id, :provider]
  end
end
