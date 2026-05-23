class AddMessagingProviderToInboxes < ActiveRecord::Migration[7.1]
  def change
    add_column :inboxes, :messaging_provider, :string,
               default: 'direct_meta', null: false
    add_index :inboxes, :messaging_provider
  end
end
