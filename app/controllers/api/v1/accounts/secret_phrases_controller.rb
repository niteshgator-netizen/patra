class Api::V1::Accounts::SecretPhrasesController < Api::V1::Accounts::BaseController
  include Patra::MainFeatureGuard

  before_action :load_phrase, only: [:show, :update, :destroy]
  # SECRETS (granted-main) — managing secret phrases is an owner power, delegable to a manager via
  # the 'secrets' grant. Owner always passes; a non-owner administrator only if granted. Reads
  # (index/show) keep their existing access; only mutations are gated (mirrors backup_pages/payment_handles).
  before_action(only: [:create, :update, :destroy]) { check_main_feature_authorization!(:secrets) }

  def index
    phrases = Current.account.secret_phrases.order(created_at: :desc)
    render json: phrases.map { |sp| serialize(sp) }
  end

  def show
    render json: serialize(@phrase)
  end

  def create
    phrase = Current.account.secret_phrases.build(phrase_params.merge(user: Current.user))
    if phrase.save
      render json: serialize(phrase), status: :created
    else
      render json: { errors: phrase.errors.full_messages }, status: :unprocessable_entity
    end
  end

  def update
    if @phrase.update(phrase_params)
      render json: serialize(@phrase)
    else
      render json: { errors: @phrase.errors.full_messages }, status: :unprocessable_entity
    end
  end

  def destroy
    @phrase.destroy
    head :no_content
  end

  private

  def load_phrase
    @phrase = Current.account.secret_phrases.find(params[:id])
  end

  def phrase_params
    params.require(:secret_phrase).permit(:phrase, :action, :active)
  end

  def serialize(sp)
    {
      id: sp.id,
      phrase: sp.phrase,
      action: sp.action,
      active: sp.active,
      trigger_count: sp.trigger_count,
      last_triggered_at: sp.last_triggered_at,
      created_at: sp.created_at
    }
  end
end
