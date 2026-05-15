# Vegas Sweeps game API client.
# Uses the IDENTICAL FastAPI/AddUser spec as Game Vault (same provider).
# Only the base URL differs. Everything else (signing, endpoints,
# error codes, verification net) inherits from Games::GameVault::Client.
module Games
  module VegasSweeps
    class Client < Games::GameVault::Client
      DEFAULT_BASE_URL = 'https://apius.lasvegassweeps.com'.freeze

      def initialize(agent_game)
        super
        # Override the base_url that the parent constructor set.
        # Use the agent_game's configured URL first, fall back to our default.
        @base_url = (agent_game.game&.api_base_url.presence || DEFAULT_BASE_URL).chomp('/')
      end

      private

      # Override credential env var fallbacks so Vegas Sweeps reads its own
      # Railway env vars, not Game Vault's.
      def env_agent_id
        ENV.fetch('VEGAS_SWEEPS_AGENT_ID', '153472')
      end

      def env_secret_key
        ENV.fetch('VEGAS_SWEEPS_SECRET_KEY', '')
      end
    end
  end
end
