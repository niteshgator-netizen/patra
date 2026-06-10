# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'PATRA_RESTRICT_MONEY_ACTIONS dark flag', type: :request do
  let(:account) { create(:account) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:pref_url) { "/api/v1/accounts/#{account.id}/reply_preference" }
  let(:payload) { { reply_preference: { reply_tone: 'friendly' } } }

  context 'when the flag is OFF (default)' do
    it 'keeps agent mutations working exactly as before' do
      patch pref_url, params: payload, headers: agent.create_new_auth_token, as: :json

      expect(response).to have_http_status(:success)
    end
  end

  context 'when the flag is ON' do
    it 'blocks agents from money-config mutations' do
      with_modified_env PATRA_RESTRICT_MONEY_ACTIONS: 'true' do
        patch pref_url, params: payload, headers: agent.create_new_auth_token, as: :json
      end

      expect(response).to have_http_status(:unauthorized)
    end

    it 'still allows administrators' do
      with_modified_env PATRA_RESTRICT_MONEY_ACTIONS: 'true' do
        patch pref_url, params: payload, headers: admin.create_new_auth_token, as: :json
      end

      expect(response).to have_http_status(:success)
    end

    it 'blocks agents from load_player' do
      agent_game = create(:agent_game, account: account)

      with_modified_env PATRA_RESTRICT_MONEY_ACTIONS: 'true' do
        post "/api/v1/accounts/#{account.id}/agent_games/#{agent_game.id}/load_player",
             params: { game_username: 'p1', amount: 5 },
             headers: agent.create_new_auth_token, as: :json
      end

      expect(response).to have_http_status(:unauthorized)
    end

    it 'keeps reads open for agents' do
      with_modified_env PATRA_RESTRICT_MONEY_ACTIONS: 'true' do
        get pref_url, headers: agent.create_new_auth_token, as: :json
      end

      expect(response).to have_http_status(:success)
    end
  end
end
