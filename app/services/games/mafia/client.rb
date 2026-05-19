module Games
  module Mafia
    class Client < Games::LaravelPanel::BaseClient
      BASE_URL = 'https://agentserver.mafia77777.com'.freeze
      PANEL_KEY = 'mafia'.freeze
    end
  end
end
