# frozen_string_literal: true

class Api::V1::Accounts::Patra::GameHealthController < Api::V1::Accounts::BaseController
  def index
    games = Current.account.agent_games.includes(:game).map do |ag|
      {
        id: ag.id,
        slug: ag.game.slug,
        name: ag.game.name,
        last_success_at: ag.last_used_at,
        failure_count: ag.failure_count,
        session_age_minutes: session_age_minutes(ag),
        status: health_status(ag)
      }
    end

    active = games.count { |g| g[:status] != 'down' }
    render json: { games: games, active_count: active, total_count: games.size }
  end

  private

  def session_age_minutes(ag)
    return nil unless ag.last_used_at

    ((Time.current - ag.last_used_at) / 60.0).round
  end

  def health_status(ag)
    return 'down' if ag.failure_count.to_i >= 3
    return 'degraded' if ag.failure_count.to_i.positive?

    'healthy'
  end
end
