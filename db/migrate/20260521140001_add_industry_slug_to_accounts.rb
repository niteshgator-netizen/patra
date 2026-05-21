class AddIndustrySlugToAccounts < ActiveRecord::Migration[7.0]
  def up
    add_column :accounts, :industry_slug, :string, default: 'sweepstakes', null: false
    add_index :accounts, :industry_slug
  end

  def down
    remove_index :accounts, :industry_slug
    remove_column :accounts, :industry_slug
  end
end
