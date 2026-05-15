module Games
  module Vblink
    class Client < Games::FastApi::Client
      DEFAULT_BASE_URL = 'https://gm.vblink777.club'.freeze

      private

      def default_base_url
        DEFAULT_BASE_URL
      end

      def env_app_id
        ENV.fetch('VBLINK_APP_ID', '')
      end

      def env_app_secret
        ENV.fetch('VBLINK_APP_SECRET', '')
      end

      def env_agent_account
        ENV.fetch('VBLINK_AGENT_ACCOUNT', '')
      end

      def env_agent_password
        ENV.fetch('VBLINK_AGENT_PASSWORD', '')
      end
    end
  end
end
