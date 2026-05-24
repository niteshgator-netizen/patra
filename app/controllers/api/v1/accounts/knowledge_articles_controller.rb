# frozen_string_literal: true

class Api::V1::Accounts::KnowledgeArticlesController < Api::V1::Accounts::BaseController
  before_action :fetch_article, only: [:show, :update, :destroy, :draft_from_conversations, :improve]

  def index
    articles = Current.account.knowledge_articles.order(updated_at: :desc)
    render json: articles
  end

  def show
    render json: @article
  end

  def create
    article = Current.account.knowledge_articles.create!(article_params.merge(created_by_user: current_user))
    render json: article, status: :created
  end

  def update
    @article.update!(article_params)
    render json: @article
  end

  def destroy
    @article.destroy!
    head :ok
  end

  def search
    query = params[:q].to_s
    articles = Current.account.knowledge_articles.published.where('title ILIKE ? OR content ILIKE ?', "%#{query}%", "%#{query}%").limit(10)
    render json: articles
  end

  def draft_from_conversations
    content = Ai::KnowledgeDrafter.draft_from_conversations(Current.account)
    @article.update!(content: content) if content.present?
    render json: @article
  end

  def improve
    improved = Ai::KnowledgeDrafter.improve(@article.content)
    @article.update!(content: improved) if improved.present?
    render json: @article
  end

  private

  def fetch_article
    @article = Current.account.knowledge_articles.find(params[:id])
  end

  def article_params
    params.permit(:title, :content, :category, :published, tags: [])
  end
end
