class Api::V1::Accounts::AgentGamesController < Api::V1::Accounts::BaseController
  before_action :fetch_agent_game, only: [:show, :update, :destroy]

  def index
    @agent_games = Current.account.agent_games.includes(:game)
    render json: serialize_collection(@agent_games)
  end

  def available_games
    @games = Game.active.with_api.ordered
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

  def test_connection
    @agent_game = Current.account.agent_games.find(params[:id])

    unless Games::ClientRegistry.supported?(@agent_game.game.slug)
      return render json: { ok: false, message: "Test connection not supported for #{@agent_game.game.name} yet" }, status: :ok
    end

    client = Games::ClientRegistry.client_for(@agent_game)
    result = client.test_connection

    if result[:ok]
      @agent_game.reset_failures! if @agent_game.failure_count > 0
      @agent_game.mark_used!
    else
      @agent_game.record_failure!
    end

    render json: result
  rescue ArgumentError => e
    render json: { ok: false, message: e.message }, status: :unprocessable_entity
  end

  def load_player
    @agent_game = Current.account.agent_games.find(params[:id])
    return render_not_supported unless Games::ClientRegistry.supported?(@agent_game.game.slug)

    username = params[:game_username].to_s.strip
    amount = params[:amount].to_f
    return render json: { ok: false, message: 'Missing game username' }, status: :unprocessable_entity if username.blank?
    return render json: { ok: false, message: 'Amount must be greater than zero' }, status: :unprocessable_entity if amount <= 0

    executor = Games::ActionExecutor.new(agent_game: @agent_game)
    result = executor.load_player(
      game_username: username,
      amount: amount,
      payment_method: params[:payment_method],
      payment_handle: params[:payment_handle],
      metadata: { source: 'manual_ui', operator_user_id: Current.user&.id }
    )

    Games::SlackNotifier.load_alert(result[:action]) if result[:ok]

    render json: serialize_action_result(result)
  rescue Games::ActionExecutor::IdempotencyError => e
    render json: { ok: false, message: e.message }, status: :conflict
  rescue StandardError => e
    Rails.logger.error("[load_player] #{e.class}: #{e.message}")
    render json: { ok: false, message: e.message }, status: :internal_server_error
  end

  def cashout_player
    @agent_game = Current.account.agent_games.find(params[:id])
    return render_not_supported unless Games::ClientRegistry.supported?(@agent_game.game.slug)

    username = params[:game_username].to_s.strip
    amount = params[:amount].to_f
    return render json: { ok: false, message: 'Missing game username' }, status: :unprocessable_entity if username.blank?
    return render json: { ok: false, message: 'Amount must be greater than zero' }, status: :unprocessable_entity if amount <= 0

    executor = Games::ActionExecutor.new(agent_game: @agent_game)
    result = executor.cashout_player(
      game_username: username,
      amount: amount,
      payment_method: params[:payment_method],
      metadata: { source: 'manual_ui', operator_user_id: Current.user&.id }
    )

    render json: serialize_action_result(result)
  rescue Games::ActionExecutor::IdempotencyError => e
    render json: { ok: false, message: e.message }, status: :conflict
  rescue StandardError => e
    Rails.logger.error("[cashout_player] #{e.class}: #{e.message}")
    render json: { ok: false, message: e.message }, status: :internal_server_error
  end

  def check_player
    @agent_game = Current.account.agent_games.find(params[:id])
    return render_not_supported unless Games::ClientRegistry.supported?(@agent_game.game.slug)

    username = params[:game_username].to_s.strip
    return render json: { ok: false, message: 'Missing game username' }, status: :unprocessable_entity if username.blank?

    executor = Games::ActionExecutor.new(agent_game: @agent_game)
    balance = executor.check_player_balance(game_username: username)

    if balance.nil?
      render json: { ok: false, message: "Player '#{username}' not found on #{@agent_game.game.name}" }
    else
      render json: { ok: true, username: username, balance: balance }
    end
  rescue StandardError => e
    Rails.logger.error("[check_player] #{e.class}: #{e.message}")
    render json: { ok: false, message: e.message }, status: :internal_server_error
  end

  def diagnose
    @agent_game = Current.account.agent_games.find(params[:id])
    return render_not_supported unless Games::ClientRegistry.supported?(@agent_game.game.slug)

    ag = @agent_game
    diag = {
      patra_egress_ip: fetch_egress_ip,
      agent_id: ag.credentials['agent_id'],
      ip_whitelist_confirmed: ag.ip_whitelist_confirmed,
      last_used_at: ag.last_used_at,
      failure_count: ag.failure_count
    }

    begin
      client = Games::ClientRegistry.client_for(ag)
      bal = client.agent_balance
      diag[:balance_call] = { ok: true, code: bal['code'], message: bal['msg'], balance: bal.dig('data', 'agent_balance') }
    rescue StandardError => e
      diag[:balance_call] = { ok: false, error: e.message }
    end

    render json: diag
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

  def render_not_supported
    render json: { ok: false, message: "Action not supported for #{@agent_game.game.name} yet" }, status: :ok
  end

  def serialize_action_result(result)
    if result[:ok]
      {
        ok: true,
        action_id: result[:action]&.id,
        order_id: result[:action]&.order_id,
        amount: result[:action]&.amount,
        game_username: result[:action]&.game_username,
        api_response: result[:response]
      }
    else
      {
        ok: false,
        action_id: result[:action]&.id,
        code: result[:code],
        message: result[:error]
      }
    end
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

  def fetch_egress_ip
    require 'net/http'
    uri = URI('https://ifconfig.me/ip')
    Net::HTTP.start(uri.host, uri.port, use_ssl: true, open_timeout: 3, read_timeout: 3) do |http|
      http.get(uri.path).body.strip
    end
  rescue StandardError => e
    "error: #{e.message}"
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
