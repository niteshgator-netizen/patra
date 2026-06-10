# frozen_string_literal: true

module Patra
  # Read-only game-connection health used by the operator console (ADM1/ADM3).
  #
  # health_status / session_age_minutes REPLICATE the private methods of
  # Api::V1::Accounts::Patra::GameHealthController. The logic is locked inside
  # that controller's action (private instance methods) and the controller is
  # outside the TAB-C lane, so it was replicated here instead of extracted.
  # KEEP IN SYNC with the controller — see PATRA_FEAT_LOG.md (ADM3).
  #
  # Never triggers live game connections: everything reads persisted
  # AgentGame columns only.
  class GameHealthQuery
    DOWN_FAILURE_THRESHOLD = 3

    class << self
      def health_status(agent_game)
        return 'down' if agent_game.failure_count.to_i >= DOWN_FAILURE_THRESHOLD
        return 'degraded' if agent_game.failure_count.to_i.positive?

        'healthy'
      end

      def session_age_minutes(agent_game)
        return nil unless agent_game.last_used_at

        ((Time.current - agent_game.last_used_at) / 60.0).round
      end

      # rows = accounts, cols = games. One query, zero per-cell SQL.
      # 🔒 Cells expose status/error text/timestamps ONLY — never credentials.
      def matrix
        games = Game.ordered.to_a
        agent_games = AgentGame.includes(:game, :account).to_a

        rows = agent_games.group_by(&:account_id).map do |account_id, account_games|
          account = account_games.first.account
          cells = account_games.index_by(&:game_id).transform_values { |ag| cell_for(ag) }
          {
            account_id: account_id,
            account_name: account&.name.to_s,
            cells: cells,
            down_count: cells.values.count { |c| c[:health] == 'down' }
          }
        end

        {
          games: games,
          rows: rows.sort_by { |r| [-r[:down_count], r[:account_name]] },
          per_game_summary: per_game_summary(games, agent_games),
          down_total: agent_games.count { |ag| health_status(ag) == 'down' }
        }
      end

      private

      def cell_for(agent_game)
        {
          health: health_status(agent_game),
          status: agent_game.status,
          connection_status: agent_game.connection_status,
          session_age_minutes: session_age_minutes(agent_game),
          last_checked_at: agent_game.last_connection_checked_at,
          # error TEXT only — model truncates to 255; never credentials
          last_error: agent_game.last_connection_ok == false ? agent_game.last_connection_message.to_s : nil,
          failure_count: agent_game.failure_count.to_i
        }
      end

      def per_game_summary(games, agent_games)
        by_game = agent_games.group_by(&:game_id)
        games.index_by(&:id).transform_values do |game|
          list = by_game[game.id] || []
          {
            game_name: game.name,
            total: list.size,
            down: list.count { |ag| health_status(ag) == 'down' },
            degraded: list.count { |ag| health_status(ag) == 'degraded' },
            healthy: list.count { |ag| health_status(ag) == 'healthy' }
          }
        end
      end
    end
  end
end
