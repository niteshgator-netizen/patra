class CreatePlayerTiers < ActiveRecord::Migration[7.0]
  def change
    create_table :player_tiers do |t|
      t.references :account, null: false, foreign_key: true
      t.string  :name, null: false
      t.string  :color, default: '#888888'
      t.string  :badge_text
      t.jsonb   :rule_overrides, default: {}
      t.integer :auto_promote_after_deposits
      t.decimal :auto_promote_deposit_threshold, precision: 10, scale: 2
      t.integer :sort_order, default: 0
      t.timestamps
    end

    add_index :player_tiers, [:account_id, :name], unique: true

    add_column :contacts, :player_tier_id, :bigint
    add_index :contacts, :player_tier_id
  end
end
