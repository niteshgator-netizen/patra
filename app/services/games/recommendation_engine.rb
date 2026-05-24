# frozen_string_literal: true

module Games
  class RecommendationEngine
    DEFAULT_RULES = {
      'juwa' => 'game_vault',
      'fire_kirin' => 'orion_stars'
    }.freeze

    def self.recommend(contact, account)
      history = GameAction.where(contact: contact, status: 'success')
                          .joins(:agent_game).group('agent_games.game_id').count
      return nil if history.empty?

      top_game_id = history.max_by { |_, count| count }&.first
      top_game = Game.find_by(id: top_game_id)
      recommended_slug = DEFAULT_RULES[top_game&.slug]
      return nil unless recommended_slug

      account.games.find_by(slug: recommended_slug)
    end

    def self.message_for(contact, account)
      game = recommend(contact, account)
      return nil unless game

      top_action = GameAction.where(contact: contact, status: 'success').joins(agent_game: :game).order(created_at: :desc).first
      top_name = top_action&.agent_game&.game&.name || 'your favorite game'
      "Have you tried #{game.name}? It's similar to #{top_name} but with better bonuses!"
    end
  end
end
