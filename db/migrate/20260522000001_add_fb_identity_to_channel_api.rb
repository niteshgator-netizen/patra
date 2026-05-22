class AddFbIdentityToChannelApi < ActiveRecord::Migration[7.0]
  def change
    add_column :channel_api, :facebook_identity_id, :bigint, null: true
    add_index :channel_api, :facebook_identity_id
  end
end
