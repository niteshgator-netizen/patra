# frozen_string_literal: true

class CreateKnowledgeArticles < ActiveRecord::Migration[7.1]
  def change
    enable_extension 'vector' unless extension_enabled?('vector')

    create_table :knowledge_articles do |t|
      t.references :account, null: false, foreign_key: true, index: true
      t.string :title, null: false
      t.text :content, null: false
      t.string :category
      t.string :tags, array: true, default: []
      t.vector :embedding, limit: 1536
      t.boolean :published, default: false, null: false
      t.references :created_by_user, foreign_key: { to_table: :users }
      t.integer :helpful_count, default: 0, null: false
      t.integer :not_helpful_count, default: 0, null: false
      t.timestamps
    end

    add_index :knowledge_articles, [:account_id, :published]
    add_index :knowledge_articles, :category
  end
end
