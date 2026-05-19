module Games
  module CashMachine
    class Client < Games::LaravelPanel::BaseClient
      BASE_URL = 'https://agentserver.cashmachine777.com'.freeze
      PANEL_KEY = 'cashmachine'.freeze
    end
  end
end
