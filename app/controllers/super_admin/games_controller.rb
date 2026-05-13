class SuperAdmin::GamesController < SuperAdmin::ApplicationController
  def index
    @games = Game.ordered
  end

  def new
    @game = Game.new
  end

  def create
    @game = Game.new(game_params)
    if @game.save
      redirect_to super_admin_games_path, notice: 'Game added to catalog.'
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
    @game = Game.find(params[:id])
  end

  def update
    @game = Game.find(params[:id])
    if @game.update(game_params)
      redirect_to super_admin_games_path, notice: 'Game updated.'
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @game = Game.find(params[:id])
    @game.destroy
    redirect_to super_admin_games_path, notice: 'Game removed from catalog.'
  end

  private

  def game_params
    params.require(:game).permit(
      :name, :slug, :logo_emoji, :logo_url, :domain,
      :player_signup_url, :agent_login_url, :api_base_url,
      :has_api, :api_docs_url, :auth_method, :description,
      :status, :sort_order, required_fields: []
    )
  end
end
