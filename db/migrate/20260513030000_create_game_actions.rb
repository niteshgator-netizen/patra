class CreateGameActions < ActiveRecord::Migration[7.1]
  def change
    create_table :game_actions do |t|
      t.bigint :account_id, null: false
      t.bigint :agent_game_id, null: false
      t.bigint :contact_id  # nullable — could be manual action with no contact
      t.bigint :conversation_id  # nullable

      t.string :action_type, null: false  # 'load', 'cashout', 'add_player', 'balance_check'
      t.string :order_id, null: false  # idempotency key, unique per account
      t.string :game_username  # the player's username on the game
      t.string :game_user_id  # the player's ID on the game (from getUserID)

      t.decimal :amount, precision: 12, scale: 2  # the dollar amount
      t.string :payment_method  # 'cashapp', 'chime', 'paypal', etc — for tracking flow
      t.string :payment_handle  # which of our handles was used

      t.string :status, default: 'pending', null: false  # 'pending', 'success', 'failed'
      t.integer :api_response_code  # Game Vault's code (0 = success)
      t.text :api_response_message
      t.jsonb :api_response_body, default: {}

      t.jsonb :metadata, default: {}  # tips, reloads, applied rules, etc.

      t.datetime :executed_at
      t.timestamps
    end

    add_index :game_actions, [:account_id, :order_id], unique: true
    add_index :game_actions, [:account_id, :action_type, :created_at]
    add_index :game_actions, :contact_id
    add_index :game_actions, :conversation_id
    add_index :game_actions, :game_username
  end
end
