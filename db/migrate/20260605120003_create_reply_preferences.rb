class CreateReplyPreferences < ActiveRecord::Migration[7.0]
  def change
    create_table :reply_preferences do |t|
      t.references :account, null: false, foreign_key: true
      t.string  :reply_tone, default: 'casual'
      t.boolean :use_emojis, default: true
      t.integer :max_reply_lines, default: 2
      t.string  :sign_off_text
      t.boolean :use_rag_examples, default: true
      t.integer :rag_example_count, default: 3
      t.boolean :confirm_before_load, default: false
      t.boolean :confirm_before_cashout, default: true
      t.boolean :auto_send_receipt, default: true
      t.timestamps
    end

    add_index :reply_preferences, :account_id, unique: true
  end
end
