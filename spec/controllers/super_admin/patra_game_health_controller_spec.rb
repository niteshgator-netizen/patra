# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Super Admin Patra game health matrix', type: :request do
  let!(:super_admin) { create(:super_admin) }

  describe 'GET /super_admin/patra_game_health' do
    it 'redirects unauthenticated users' do
      get '/super_admin/patra_game_health'
      expect(response).to have_http_status(:redirect)
    end

    it 'renders the matrix read-only with mocked statuses' do
      allow(Patra::GameHealthQuery).to receive(:matrix).and_return(
        {
          games: [],
          rows: [],
          per_game_summary: {},
          down_total: 0
        }
      )
      sign_in(super_admin, scope: :super_admin)
      get '/super_admin/patra_game_health'
      expect(response).to have_http_status(:success)
      expect(response.body).to include('Game Health Matrix')
      expect(response.body).to include('No game connections exist yet')
      expect(Patra::GameHealthQuery).to have_received(:matrix)
    end
  end
end
