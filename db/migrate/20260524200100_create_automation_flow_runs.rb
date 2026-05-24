# frozen_string_literal: true

class CreateAutomationFlowRuns < ActiveRecord::Migration[7.1]
  def change
    create_table :automation_flow_runs do |t|
      t.references :automation_flow, null: false, foreign_key: true, index: true
      t.references :conversation, foreign_key: true, index: true
      t.references :contact, foreign_key: true, index: true
      t.string :current_step_id
      t.string :status, null: false, default: 'running'
      t.datetime :started_at, null: false
      t.datetime :completed_at
      t.jsonb :step_log, default: [], null: false
      t.boolean :preview_mode, default: false, null: false
      t.timestamps
    end

    add_index :automation_flow_runs, [:automation_flow_id, :status]
  end
end
