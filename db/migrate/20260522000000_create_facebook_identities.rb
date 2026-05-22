class CreateFacebookIdentities < ActiveRecord::Migration[7.0]
  def change
    create_table :facebook_identities do |t|
      t.references :account, null: false, foreign_key: true
      t.string :fb_user_id, null: false
      t.string :fb_user_name
      t.string :fb_user_avatar_url
      t.text :user_access_token
      t.datetime :token_expires_at
      t.datetime :token_last_refreshed_at
      t.string :status, default: 'active', null: false
      t.timestamps
    end
    add_index :facebook_identities, [:account_id, :fb_user_id], unique: true
    add_index :facebook_identities, [:account_id, :status]
  end
end
