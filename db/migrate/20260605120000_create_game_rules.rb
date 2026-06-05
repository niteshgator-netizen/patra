class CreateGameRules < ActiveRecord::Migration[7.0]
  def change
    create_table :game_rules do |t|
      t.references :account, null: false, foreign_key: true
      t.references :game, null: false, foreign_key: true

      # Freeplay
      t.boolean :freeplay_enabled, default: false
      t.decimal :freeplay_amount, precision: 10, scale: 2, default: 5.0
      t.integer :freeplay_max_per_day, default: 1
      t.integer :freeplay_max_per_week, default: 3
      t.string  :freeplay_eligible_tiers, default: '["new_player"]'
      t.decimal :freeplay_cashout_min_multiplier, precision: 5, scale: 2, default: 5.0
      t.decimal :freeplay_cashout_max_amount, precision: 10, scale: 2, default: 50.0
      t.boolean :freeplay_require_deposit_first, default: false
      t.string  :freeplay_message, default: 'fp loaded ✅'

      # Deposit bonus
      t.boolean :deposit_bonus_enabled, default: false
      t.integer :deposit_bonus_percentage, default: 20
      t.decimal :deposit_bonus_min_amount, precision: 10, scale: 2, default: 10.0
      t.decimal :deposit_bonus_max_bonus, precision: 10, scale: 2, default: 100.0
      t.string  :deposit_bonus_eligible_tiers, default: '["all"]'
      t.boolean :deposit_bonus_first_deposit_only, default: false
      t.string  :deposit_bonus_message, default: 'Loaded with {bonus_pct}% bonus ✅'

      # Cashout
      t.boolean :cashout_enabled, default: true
      t.decimal :cashout_min_multiplier, precision: 5, scale: 2, default: 4.0
      t.decimal :cashout_max_multiplier, precision: 5, scale: 2, default: 10.0
      t.decimal :cashout_max_amount, precision: 10, scale: 2, default: 250.0
      t.decimal :cashout_min_amount, precision: 10, scale: 2, default: 10.0
      t.decimal :cashout_freeplay_multiplier, precision: 5, scale: 2, default: 5.0
      t.decimal :cashout_freeplay_max, precision: 10, scale: 2, default: 50.0
      t.text    :cashout_rules_text
      t.boolean :cashout_require_screenshot, default: false

      # Links
      t.string  :game_download_url
      t.string  :game_web_url
      t.boolean :auto_send_link_on_create, default: true
      t.text    :game_info_message

      t.timestamps
    end

    add_index :game_rules, [:account_id, :game_id], unique: true
  end
end
