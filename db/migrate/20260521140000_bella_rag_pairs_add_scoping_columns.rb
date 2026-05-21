class BellaRagPairsAddScopingColumns < ActiveRecord::Migration[7.0]
  def up
    add_reference :bella_rag_pairs, :account, foreign_key: { to_table: :accounts }, null: true, index: true
    add_column :bella_rag_pairs, :industry_slug, :string, null: true
    add_column :bella_rag_pairs, :source, :string, default: 'upload', null: false
    add_column :bella_rag_pairs, :approved, :boolean, default: true, null: false
    add_column :bella_rag_pairs, :anonymized, :boolean, default: false, null: false
    add_column :bella_rag_pairs, :created_by_user_id, :bigint, null: true

    add_index :bella_rag_pairs, :industry_slug
    add_index :bella_rag_pairs, [:account_id, :industry_slug, :approved], name: 'index_bella_rag_pairs_on_scoping'

    # Backfill: existing 73k pairs are Genius's sweepstakes data → industry baseline.
    # account_id stays NULL (industry-level), industry_slug='sweepstakes', approved=true, source='upload'
    execute <<~SQL
      UPDATE bella_rag_pairs
      SET industry_slug = 'sweepstakes',
          source = 'upload',
          approved = true,
          anonymized = false
      WHERE industry_slug IS NULL
    SQL
    puts "[migration] backfilled #{BellaRagPair.where(industry_slug: 'sweepstakes').count} pairs as sweepstakes industry baseline"
  end

  def down
    remove_index :bella_rag_pairs, name: 'index_bella_rag_pairs_on_scoping'
    remove_index :bella_rag_pairs, :industry_slug
    remove_column :bella_rag_pairs, :created_by_user_id
    remove_column :bella_rag_pairs, :anonymized
    remove_column :bella_rag_pairs, :approved
    remove_column :bella_rag_pairs, :source
    remove_column :bella_rag_pairs, :industry_slug
    remove_reference :bella_rag_pairs, :account
  end
end
