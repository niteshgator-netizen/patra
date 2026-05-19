module Games
  module OrionStars
    class Client < Games::AspNetPanel::BaseClient
      BASE_URL = 'https://orionstars.vip:8781'.freeze
    end
  end
end
