class Api::V1::Accounts::AgentGamesController < Api::V1::Accounts::BaseController
  before_action :fetch_agent_game, only: [:show, :update, :destroy]

  def index
    @agent_games = Current.account.agent_games.includes(:game)
    render json: serialize_collection(@agent_games)
  end

  def available_games
    @games = Game.active.ordered
    render json: @games.map { |g| serialize_game(g) }
  end

  def show
    render json: serialize_one(@agent_game)
  end

  def create
    game = Game.active.find(params[:game_id])
    @agent_game = Current.account.agent_games.build(
      game: game,
      status: params[:status] || 'inactive',
      credentials: params[:credentials] || {},
      display_name: params[:display_name],
      notes: params[:notes],
      ip_whitelist_confirmed: params[:ip_whitelist_confirmed] || false
    )
    if @agent_game.save
      render json: serialize_one(@agent_game), status: :created
    else
      render json: { errors: @agent_game.errors.full_messages }, status: :unprocessable_entity
    end
  end

  def update
    if @agent_game.update(update_params)
      render json: serialize_one(@agent_game)
    else
      render json: { errors: @agent_game.errors.full_messages }, status: :unprocessable_entity
    end
  end

  def destroy
    @agent_game.destroy
    head :no_content
  end

  private

  def fetch_agent_game
    @agent_game = Current.account.agent_games.find(params[:id])
  end

  def update_params
    permitted = params.permit(:status, :display_name, :notes, :ip_whitelist_confirmed, credentials: {})
    if permitted[:credentials].present? && @agent_game.credentials.is_a?(Hash)
      permitted[:credentials] = @agent_game.credentials.merge(permitted[:credentials])
    end
    permitted
  end

  def serialize_collection(agent_games)
    agent_games.map { |ag| serialize_one(ag) }
  end

  def serialize_one(ag)
    {
      id: ag.id,
      game: serialize_game(ag.game),
      status: ag.status,
      display_name: ag.display_name,
      display_label: ag.display_label,
      notes: ag.notes,
      ip_whitelist_confirmed: ag.ip_whitelist_confirmed,
      api_configured: ag.api_configured?,
      credentials: ag.safe_credentials,
      failure_count: ag.failure_count,
      last_used_at: ag.last_used_at,
      last_failure_at: ag.last_failure_at,
      created_at: ag.created_at,
      updated_at: ag.updated_at
    }
  end

  def serialize_game(game)
    {
      id: game.id,
      name: game.name,
      slug: game.slug,
      logo_emoji: game.logo_emoji,
      logo_url: game.logo_url,
      domain: game.domain,
      player_signup_url: game.player_signup_url,
      agent_login_url: game.agent_login_url,
      api_base_url: game.api_base_url,
      has_api: game.has_api,
      api_docs_url: game.api_docs_url,
      auth_method: game.auth_method,
      required_fields: game.required_fields,
      description: game.description
    }
  end
end
