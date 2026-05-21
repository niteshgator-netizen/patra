class CreateBellaTakeoverCandidates < ActiveRecord::Migration[7.0]
  def change
    create_table :bella_takeover_candidates do |t|
      t.references :account, null: false, foreign_key: true
      t.references :conversation, null: false, foreign_key: true
      t.references :message, null: false, foreign_key: true
      t.text :customer_text, null: false
      t.text :human_reply, null: false
      t.float :confidence_score, null: false, default: 0.0
      t.string :status, default: 'queued', null: false
      t.bigint :resulting_pair_id
      t.timestamps
    end
    add_index :bella_takeover_candidates, [:account_id, :status]
    add_index :bella_takeover_candidates, :resulting_pair_id
  end
end
