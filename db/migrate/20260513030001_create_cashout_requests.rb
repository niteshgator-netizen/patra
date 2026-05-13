class CreateCashoutRequests < ActiveRecord::Migration[7.1]
  def change
    create_table :cashout_requests do |t|
      t.bigint :account_id, null: false
      t.bigint :agent_game_id, null: false
      t.bigint :contact_id, null: false
      t.bigint :conversation_id

      t.string :player_name
      t.string :game_username, null: false

      t.decimal :total_points, precision: 12, scale: 2
      t.decimal :cashout_amount, precision: 12, scale: 2, null: false
      t.decimal :remaining_points, precision: 12, scale: 2, default: 0
      t.decimal :tip_amount, precision: 12, scale: 2, default: 0
      t.decimal :reload_amount, precision: 12, scale: 2, default: 0

      t.decimal :original_deposit, precision: 12, scale: 2
      t.string :deposit_payment_method
      t.string :cashout_payment_method
      t.string :cashout_destination_handle  # customer's CashApp/Chime tag

      t.jsonb :applied_rules, default: []  # which canned-response rules applied
      t.text :customer_message  # what the customer actually said

      t.string :status, default: 'pending', null: false  # 'pending', 'approved', 'paid', 'rejected'
      t.string :slack_message_ts  # Slack message timestamp for threading replies

      t.bigint :withdraw_action_id  # FK to game_actions when withdraw executed
      t.bigint :reload_action_id  # FK to game_actions when reload executed

      t.timestamps
    end

    add_index :cashout_requests, [:account_id, :status, :created_at]
    add_index :cashout_requests, :contact_id
    add_index :cashout_requests, :game_username
  end
end
