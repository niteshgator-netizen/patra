# frozen_string_literal: true

class CreateAgentGames < ActiveRecord::Migration[7.1]
  def change
    create_table :agent_games do |t|
      t.references :account, null: false, foreign_key: { on_delete: :cascade }, index: false, type: :bigint
      t.references :game, null: false, foreign_key: { on_delete: :cascade }, index: false, type: :bigint
      t.string :status, default: 'inactive', null: false
      t.jsonb :credentials, default: {}, null: false
      t.string :display_name
      t.text :notes
      t.boolean :ip_whitelist_confirmed, default: false, null: false
      t.datetime :last_used_at
      t.datetime :last_failure_at
      t.integer :failure_count, default: 0, null: false
      t.timestamps
    end

    add_index :agent_games, %i[account_id game_id], unique: true
    add_index :agent_games, %i[account_id status]
    add_index :agent_games, :game_id
  end
end
