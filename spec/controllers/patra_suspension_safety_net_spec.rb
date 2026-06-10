# frozen_string_literal: true

require 'rails_helper'

# ADM7: suspension safety-net. Proves the two public Patra surfaces that
# previously ignored Account#status now refuse suspended accounts, and that
# the verified API-base enforcement still bites.
RSpec.describe 'Patra suspension safety net', type: :request do
  let!(:account) { create(:account) }

  describe 'POST /widget/patra/messages (public embeddable widget)' do
    let!(:web_widget) { create(:channel_widget, account: account) }

    it 'accepts messages for active accounts' do
      post '/widget/patra/messages',
           params: { website_token: web_widget.website_token, content: 'hi', name: 'Vis' }
      expect(response).to have_http_status(:success)
    end

    it 'rejects messages for suspended accounts with 401' do
      account.suspended!
      expect do
        post '/widget/patra/messages',
             params: { website_token: web_widget.website_token, content: 'hi', name: 'Vis' }
      end.not_to change(Message, :count)
      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe 'GET /help/:account_id (public help center)' do
    it 'serves active accounts' do
      get "/help/#{account.id}"
      expect(response).to have_http_status(:success)
    end

    it 'returns 404 for suspended accounts (index, show, search, feedback)' do
      article = KnowledgeArticle.create!(account: account, title: 'T', content: 'C', published: true)
      account.suspended!

      get "/help/#{account.id}"
      expect(response).to have_http_status(:not_found)
      get "/help/#{account.id}/articles/#{article.id}"
      expect(response).to have_http_status(:not_found)
      get "/help/#{account.id}/search", params: { q: 'T' }
      expect(response).to have_http_status(:not_found)
      post "/help/#{account.id}/articles/#{article.id}/feedback", params: { helpful: 'true' }
      expect(response).to have_http_status(:not_found)
    end
  end

  describe 'API base enforcement (verified existing behavior, not new code)' do
    it 'blocks suspended accounts at /api/v1 with 401 on the next request' do
      user = create(:user, account: account, role: :administrator)
      account.suspended!
      get "/api/v1/accounts/#{account.id}/conversations", headers: user.create_new_auth_token
      expect(response).to have_http_status(:unauthorized)
    end
  end
end
