class CreateSecretPhrases < ActiveRecord::Migration[7.0]
  def change
    create_table :secret_phrases do |t|
      t.references :account, null: false, foreign_key: true
      t.references :user, null: false, foreign_key: true
      t.text :phrase, null: false
      t.string :action, default: 'notify_only', null: false
      t.datetime :last_triggered_at
      t.integer :trigger_count, default: 0, null: false
      t.boolean :active, default: true, null: false
      t.timestamps
    end
    add_index :secret_phrases, [:account_id, :active]
  end
end
