class AddActionTypeToBellaRagPairs < ActiveRecord::Migration[7.0]
  def change
    add_column :bella_rag_pairs, :action_type, :string
    add_index  :bella_rag_pairs, :action_type
  end
end
