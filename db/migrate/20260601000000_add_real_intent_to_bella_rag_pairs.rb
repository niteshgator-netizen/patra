class AddRealIntentToBellaRagPairs < ActiveRecord::Migration[7.0]
  def change
    add_column :bella_rag_pairs, :real_intent, :string unless column_exists?(:bella_rag_pairs, :real_intent)
    add_column :bella_rag_pairs, :real_intent_confidence, :string unless column_exists?(:bella_rag_pairs, :real_intent_confidence)
    add_column :bella_rag_pairs, :real_intent_reason, :text unless column_exists?(:bella_rag_pairs, :real_intent_reason)
    add_index  :bella_rag_pairs, :real_intent unless index_exists?(:bella_rag_pairs, :real_intent)
  end
end
