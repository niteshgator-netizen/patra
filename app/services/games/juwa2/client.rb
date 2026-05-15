module Games
  module Juwa2
    class Client < Games::GameVault::Client
      DEFAULT_BASE_URL = 'https://apiinterface.juwa2.xin'.freeze

      def initialize(agent_game)
        super
        @base_url = (agent_game.game&.api_base_url.presence || DEFAULT_BASE_URL).chomp('/')
      end

      private

      def env_agent_id
        ENV.fetch('JUWA2_AGENT_ID', '1009')
      end

      def env_secret_key
        ENV.fetch('JUWA2_SECRET_KEY', '')
      end
    end
  end
end
