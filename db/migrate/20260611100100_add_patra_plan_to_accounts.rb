class AddPatraPlanToAccounts < ActiveRecord::Migration[7.1]
  def change
    # Additive only — nullable column, no foreign key constraint so the
    # accounts table is never locked against a small lookup table.
    add_column :accounts, :patra_plan_id, :bigint
    add_index :accounts, :patra_plan_id
  end
end
