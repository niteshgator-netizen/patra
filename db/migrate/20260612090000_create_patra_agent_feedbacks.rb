# frozen_string_literal: true

# patra-final P3: agents send feedback to the owner (never to players).
# conversation_id / contact_id are optional context links (internal ids,
# no FK constraints — additive and safe on a live DB).
class CreatePatraAgentFeedbacks < ActiveRecord::Migration[7.1]
  def change
    create_table :patra_agent_feedbacks do |t|
      t.bigint :account_id, null: false
      t.bigint :user_id, null: false
      t.bigint :conversation_id
      t.bigint :contact_id
      t.text :body, null: false
      t.integer :category, default: 0, null: false
      t.integer :status, default: 0, null: false
      t.timestamps
    end

    add_index :patra_agent_feedbacks, [:account_id, :created_at]
    add_index :patra_agent_feedbacks, [:account_id, :status]
    add_index :patra_agent_feedbacks, :user_id
  end
end
