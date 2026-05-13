class AddCashoutFieldsToCashoutRequests < ActiveRecord::Migration[7.1]
  def change
    unless column_exists?(:cashout_requests, :cashout_destination_handle)
      add_column :cashout_requests, :cashout_destination_handle, :string
    end
    unless column_exists?(:cashout_requests, :withdraw_action_id)
      add_column :cashout_requests, :withdraw_action_id, :bigint
    end
    unless column_exists?(:cashout_requests, :reload_action_id)
      add_column :cashout_requests, :reload_action_id, :bigint
    end
  end
end
