# frozen_string_literal: true

class HelpCenterController < ActionController::Base
  layout false

  def index
    @account = find_account
    return head :not_found unless @account

    @articles = @account.knowledge_articles.published.order(:category, :title)
    @categories = @articles.pluck(:category).compact.uniq
  end

  def show
    @account = find_account
    @article = @account.knowledge_articles.published.find(params[:id])
  end

  def search
    @account = find_account
    query = params[:q].to_s
    @articles = @account.knowledge_articles.published.where('title ILIKE ? OR content ILIKE ?', "%#{query}%", "%#{query}%")
    render :index
  end

  def feedback
    account = find_account
    article = account.knowledge_articles.find(params[:id])
    article.record_feedback!(helpful: params[:helpful] == 'true')
    head :ok
  end

  private

  def find_account
    Account.find_by(id: params[:account_id]) || Portal.find_by(slug: params[:slug])&.account
  end
end
