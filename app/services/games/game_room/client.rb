module Games
  module GameRoom
    class Client < Games::LaravelPanel::BaseClient
      BASE_URL = 'https://agentserver.gameroom777.com'.freeze
      PANEL_KEY = 'gameroom'.freeze
    end
  end
end
