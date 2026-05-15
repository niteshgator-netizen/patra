module Games
  module UltraPanda
    class Client < Games::FastApi::Client
      DEFAULT_BASE_URL = 'https://ht.ultrapanda.mobi'.freeze

      private

      def default_base_url
        DEFAULT_BASE_URL
      end

      def env_app_id
        ENV.fetch('ULTRA_PANDA_APP_ID', '')
      end

      def env_app_secret
        ENV.fetch('ULTRA_PANDA_APP_SECRET', '')
      end

      def env_agent_account
        ENV.fetch('ULTRA_PANDA_AGENT_ACCOUNT', '')
      end

      def env_agent_password
        ENV.fetch('ULTRA_PANDA_AGENT_PASSWORD', '')
      end
    end
  end
end
