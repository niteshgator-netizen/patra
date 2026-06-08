class AddNameToNotificationChannels < ActiveRecord::Migration[7.0]
  def change
    add_column :notification_channels, :name, :string
  end
end
