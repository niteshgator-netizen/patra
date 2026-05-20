class CreateBellaRagPairs < ActiveRecord::Migration[7.0]
  def change
    enable_extension 'vector' unless extension_enabled?('vector')

    create_table :bella_rag_pairs do |t|
      t.text   :customer_text,     null: false
      t.text   :cashier_text,      null: false
      t.jsonb  :context_prev,      default: []
      t.text   :cashier_names,     array: true, default: []
      t.string :page
      t.bigint :ts_ms
      t.integer :participant_count
      t.text   :embed_input,       null: false
      t.column :embedding, :vector, limit: 512
      t.string :embedding_model,   default: 'voyage-3-lite', null: false
      t.string :industry,          default: 'sweepstakes',   null: false
      t.string :persona,           default: 'bella',         null: false
      t.timestamps
    end

    add_index :bella_rag_pairs, :industry
    add_index :bella_rag_pairs, :persona
    add_index :bella_rag_pairs, :page
    add_index :bella_rag_pairs, :embed_input, length: 200, name: 'idx_bella_rag_pairs_embed_input_prefix'

    # HNSW index with cosine distance.
    # HNSW is preferred over ivfflat for pgvector 0.5+ because it doesn't
    # require pre-loaded data for good cluster selection and gives faster
    # queries at the cost of slightly more memory. For 73k vectors @ 512 dim
    # this is ~150MB of RAM, which is well within budget.
    execute <<~SQL
      CREATE INDEX bella_rag_pairs_embedding_idx
      ON bella_rag_pairs
      USING hnsw (embedding vector_cosine_ops);
    SQL
  end
end
