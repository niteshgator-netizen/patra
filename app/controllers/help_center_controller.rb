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
    return head :not_found unless @account

    @article = @account.knowledge_articles.published.find(params[:id])
  end

  def search
    @account = find_account
    return head :not_found unless @account

    query = params[:q].to_s
    @articles = @account.knowledge_articles.published.where('title ILIKE ? OR content ILIKE ?', "%#{query}%", "%#{query}%")
    render :index
  end

  def feedback
    account = find_account
    return head :not_found unless account

    article = account.knowledge_articles.find(params[:id])
    article.record_feedback!(helpful: params[:helpful] == 'true')
    head :ok
  end

  private

  # PATRA TAB-C (ADM7): suspended accounts disappear from the public help
  # center (was also a 500 on unknown ids in show/search/feedback — now 404).
  def find_account
    account = Account.find_by(id: params[:account_id]) || Portal.find_by(slug: params[:slug])&.account
    account&.active? ? account : nil
  end
end
