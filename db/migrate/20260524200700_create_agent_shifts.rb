# frozen_string_literal: true

class CreateAgentShifts < ActiveRecord::Migration[7.1]
  def change
    create_table :agent_shifts do |t|
      t.references :account, null: false, foreign_key: true, index: true
      t.references :user, null: false, foreign_key: true, index: true
      t.integer :day_of_week, null: false
      t.time :start_time, null: false
      t.time :end_time, null: false
      t.boolean :active, default: true, null: false
      t.timestamps
    end

    add_index :agent_shifts, [:account_id, :user_id, :day_of_week]
  end
end
