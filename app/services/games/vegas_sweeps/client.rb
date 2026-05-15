# Vegas Sweeps game API client.
# Uses the IDENTICAL FastAPI/AddUser spec as Game Vault (same provider).
# Only the base URL differs. Everything else (signing, endpoints,
# error codes, verification net) inherits from Games::GameVault::Client.
module Games
  module VegasSweeps
    class Client < Games::GameVault::Client
      DEFAULT_BASE_URL = 'https://apius.lasvegassweeps.com'.freeze

      private

      def base_url_default
        DEFAULT_BASE_URL
      end

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
