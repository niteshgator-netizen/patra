# frozen_string_literal: true

class CreateDripCampaigns < ActiveRecord::Migration[7.1]
  def change
    create_table :drip_campaigns do |t|
      t.references :account, null: false, foreign_key: true, index: true
      t.references :automation_flow, null: false, foreign_key: true, index: true
      t.jsonb :contact_segment, default: {}, null: false
      t.string :status, null: false, default: 'draft'
      t.datetime :scheduled_at
      t.jsonb :stats, default: { processed: 0, completed: 0, failed: 0 }, null: false
      t.timestamps
    end

    add_index :drip_campaigns, [:account_id, :status]
  end
end
