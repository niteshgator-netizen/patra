class BellaRagPairsAddScopingColumns < ActiveRecord::Migration[7.0]
  disable_ddl_transaction!

  def up
    # Schema changes (each runs independently now)
    unless column_exists?(:bella_rag_pairs, :account_id)
      add_reference :bella_rag_pairs, :account, foreign_key: { to_table: :accounts }, null: true, index: true
    end
    unless column_exists?(:bella_rag_pairs, :industry_slug)
      add_column :bella_rag_pairs, :industry_slug, :string, null: true
    end
    unless column_exists?(:bella_rag_pairs, :source)
      add_column :bella_rag_pairs, :source, :string, default: 'upload', null: false
    end
    unless column_exists?(:bella_rag_pairs, :approved)
      add_column :bella_rag_pairs, :approved, :boolean, default: true, null: false
    end
    unless column_exists?(:bella_rag_pairs, :anonymized)
      add_column :bella_rag_pairs, :anonymized, :boolean, default: false, null: false
    end
    unless column_exists?(:bella_rag_pairs, :created_by_user_id)
      add_column :bella_rag_pairs, :created_by_user_id, :bigint, null: true
    end

    unless index_exists?(:bella_rag_pairs, :industry_slug)
      add_index :bella_rag_pairs, :industry_slug
    end
    unless index_exists?(:bella_rag_pairs, [:account_id, :industry_slug, :approved], name: 'index_bella_rag_pairs_on_scoping')
      add_index :bella_rag_pairs, [:account_id, :industry_slug, :approved], name: 'index_bella_rag_pairs_on_scoping'
    end

    # Batched backfill — each batch commits independently, well under statement_timeout
    say_with_time "Backfilling bella_rag_pairs.industry_slug to 'sweepstakes' in batches of 5000" do
      total = 0
      BellaRagPair.where(industry_slug: nil).in_batches(of: 5000) do |batch|
        batch.update_all(industry_slug: 'sweepstakes')
        total += batch.size
        puts "  [migration] backfilled batch, running total=#{total}"
      end
      puts "[migration] backfill complete: #{total} pairs set to sweepstakes industry baseline"
      total
    end
  end

  def down
    remove_index :bella_rag_pairs, name: 'index_bella_rag_pairs_on_scoping' if index_exists?(:bella_rag_pairs, [:account_id, :industry_slug, :approved], name: 'index_bella_rag_pairs_on_scoping')
    remove_index :bella_rag_pairs, :industry_slug if index_exists?(:bella_rag_pairs, :industry_slug)
    remove_column :bella_rag_pairs, :created_by_user_id if column_exists?(:bella_rag_pairs, :created_by_user_id)
    remove_column :bella_rag_pairs, :anonymized if column_exists?(:bella_rag_pairs, :anonymized)
    remove_column :bella_rag_pairs, :approved if column_exists?(:bella_rag_pairs, :approved)
    remove_column :bella_rag_pairs, :source if column_exists?(:bella_rag_pairs, :source)
    remove_column :bella_rag_pairs, :industry_slug if column_exists?(:bella_rag_pairs, :industry_slug)
    remove_reference :bella_rag_pairs, :account if column_exists?(:bella_rag_pairs, :account_id)
  end
end
