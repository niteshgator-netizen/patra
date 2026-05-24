# frozen_string_literal: true

class CreatePlayerBonuses < ActiveRecord::Migration[7.1]
  def change
    create_table :player_bonuses do |t|
      t.references :account, null: false, foreign_key: true, index: true
      t.references :contact, null: false, foreign_key: true, index: true
      t.string :game_slug
      t.decimal :amount, precision: 12, scale: 2, null: false
      t.string :reason
      t.references :given_by_user, null: false, foreign_key: { to_table: :users }
      t.datetime :created_at, null: false
    end

    add_index :player_bonuses, [:account_id, :contact_id]
  end
end
