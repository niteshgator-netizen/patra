class CreateBellaRagUploads < ActiveRecord::Migration[7.0]
  def change
    create_table :bella_rag_uploads do |t|
      t.references :account, null: false, foreign_key: true
      t.references :user, null: false, foreign_key: true
      t.string :filename, null: false
      t.integer :file_size_bytes
      t.string :status, default: 'pending', null: false
      t.integer :pairs_created, default: 0
      t.integer :pairs_skipped, default: 0
      t.text :error_message
      t.text :raw_content
      t.timestamps
    end
    add_index :bella_rag_uploads, [:account_id, :status]
  end
end
