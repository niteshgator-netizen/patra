# Additive, nullable-only. Stores the result of the last READ-ONLY test_connection
# so the games dashboard badge reflects the REAL connection state instead of the
# static api_configured? config flag. No data loss; null last_connection_ok = never tested.
class AddConnectionTestToAgentGames < ActiveRecord::Migration[7.0]
  def change
    add_column :agent_games, :last_connection_ok, :boolean
    add_column :agent_games, :last_connection_checked_at, :datetime
    add_column :agent_games, :last_connection_message, :string
  end
end
