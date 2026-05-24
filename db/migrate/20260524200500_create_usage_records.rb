# frozen_string_literal: true

class CreateUsageRecords < ActiveRecord::Migration[7.1]
  def change
    create_table :usage_records do |t|
      t.references :account, null: false, foreign_key: true, index: true
      t.string :metric, null: false
      t.integer :quantity, default: 0, null: false
      t.datetime :period_start, null: false
      t.datetime :period_end, null: false
      t.timestamps
    end

    add_index :usage_records, [:account_id, :metric, :period_start], name: 'index_usage_records_on_account_metric_period'
  end
end
