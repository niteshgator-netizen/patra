class AddByocMetaAppToAccounts < ActiveRecord::Migration[7.0]
  def change
    add_column :accounts, :meta_app_id, :string
    add_column :accounts, :meta_app_secret_encrypted, :text
    add_column :accounts, :meta_app_validated_at, :datetime
    add_index :accounts, :meta_app_id, where: 'meta_app_id IS NOT NULL'
  end
end
