# frozen_string_literal: true

class CreateAccountEntitlements < ActiveRecord::Migration[7.1]
  def change
    create_table :account_entitlements do |t|
      t.references :account, null: false, foreign_key: true, index: { unique: true }
      t.string :plan_slug, null: false, default: 'free'
      t.jsonb :limits, default: {}, null: false
      t.timestamps
    end
  end
end
