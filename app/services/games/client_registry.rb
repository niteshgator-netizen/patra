# Maps game slug -> client class. Universal interface contract:
# Every client must:
#   - Accept agent_game in constructor: Client.new(agent_game)
#   - Implement: agent_balance, user_balance, get_user_id, add_user,
#     recharge, withdraw, reset_player_password, force_player_offline,
#     test_connection
#
# To add a new game with API support:
#   1. Create Games::YourGame::Client class following the pattern above
#   2. Add one line to REGISTRY below
#   3. Update seed migration with required_fields + has_api: true
# That's it. Diagnose, Test Connection, Manage Players, Bella orchestrator,
# Telegram alerts — all work automatically.
module Games
  module ClientRegistry
    REGISTRY = {
      'game_vault' => 'Games::GameVault::Client',
      'juwa'       => 'Games::Juwa::Client'
    }.freeze

    def self.client_for(agent_game)
      klass_name = REGISTRY[agent_game.game.slug.to_s]
      return nil unless klass_name

      klass_name.constantize.new(agent_game)
    end

    def self.supported?(slug)
      REGISTRY.key?(slug.to_s)
    end

    def self.supported_slugs
      REGISTRY.keys
    end
  end
end
