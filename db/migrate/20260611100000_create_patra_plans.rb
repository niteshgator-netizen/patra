class CreatePatraPlans < ActiveRecord::Migration[7.1]
  def change
    create_table :patra_plans do |t|
      t.string :name, null: false
      # Price stays nil until Genius types one in — the UI never invents a number.
      t.decimal :price, precision: 12, scale: 2
      t.string :currency, null: false, default: 'USD'
      t.string :period, null: false, default: 'monthly'
      t.integer :agents_limit
      t.integer :inboxes_limit
      t.integer :ai_replies_monthly_limit
      t.jsonb :features, null: false, default: {}
      t.boolean :active, null: false, default: true
      t.integer :position, null: false, default: 0
      t.timestamps
    end
    add_index :patra_plans, :name, unique: true
  end
end
