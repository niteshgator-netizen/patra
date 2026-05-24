# frozen_string_literal: true

class CreateAutomationFlows < ActiveRecord::Migration[7.1]
  def change
    create_table :automation_flows do |t|
      t.references :account, null: false, foreign_key: true, index: true
      t.string :name, null: false
      t.text :description
      t.string :trigger_type, null: false
      t.jsonb :trigger_config, default: {}, null: false
      t.jsonb :steps, default: [], null: false
      t.boolean :active, default: false, null: false
      t.integer :version, default: 1, null: false
      t.references :created_by_user, foreign_key: { to_table: :users }
      t.jsonb :stats, default: { runs: 0, completions: 0, failures: 0 }, null: false
      t.timestamps
    end

    add_index :automation_flows, [:account_id, :active]
    add_index :automation_flows, [:account_id, :trigger_type]
  end
end
