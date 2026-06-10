require 'rails_helper'

RSpec.describe 'Patra tenancy/auth hardening', type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:agent) { create(:user, account: account, role: :agent) }

  describe 'incident endpoints' do
    it 'blocks agents from pause_ai' do
      post "/api/v1/accounts/#{account.id}/patra/incident/pause_ai",
           headers: agent.create_new_auth_token, as: :json

      expect(response).to have_http_status(:unauthorized)
    end

    it 'allows admins to pause_ai' do
      post "/api/v1/accounts/#{account.id}/patra/incident/pause_ai",
           headers: admin.create_new_auth_token, as: :json

      expect(response).to have_http_status(:success)
      expect(account.reload.custom_attributes['ai_paused']).to be true
    end

    it 'blocks agents from broadcast_open' do
      post "/api/v1/accounts/#{account.id}/patra/incident/broadcast_open",
           params: { message: 'hi' }, headers: agent.create_new_auth_token, as: :json

      expect(response).to have_http_status(:unauthorized)
    end

    it 'rejects blank broadcast messages even for admins' do
      post "/api/v1/accounts/#{account.id}/patra/incident/broadcast_open",
           params: { message: '   ' }, headers: admin.create_new_auth_token, as: :json

      expect(response).to have_http_status(:unprocessable_entity)
    end

    it 'blocks agents from reassign_all' do
      post "/api/v1/accounts/#{account.id}/patra/incident/reassign_all",
           params: { from_user_id: agent.id, to_user_id: admin.id },
           headers: agent.create_new_auth_token, as: :json

      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe 'holidays inbox ownership' do
    let(:other_account) { create(:account) }
    let(:foreign_inbox) { create(:inbox, account: other_account) }

    it 'rejects an inbox_id belonging to another account' do
      post "/api/v1/accounts/#{account.id}/patra/holidays",
           params: { closed_on: Date.current, name: 'X', inbox_id: foreign_inbox.id },
           headers: admin.create_new_auth_token, as: :json

      expect(response).to have_http_status(:unprocessable_entity)
      expect(account.holidays.count).to eq(0)
    end

    it 'accepts an inbox belonging to the account' do
      inbox = create(:inbox, account: account)

      post "/api/v1/accounts/#{account.id}/patra/holidays",
           params: { closed_on: Date.current, name: 'X', inbox_id: inbox.id },
           headers: admin.create_new_auth_token, as: :json

      expect(response).to have_http_status(:created)
    end
  end

  describe 'referral settings admin gate' do
    it 'blocks agents from updating referral settings' do
      put "/api/v1/accounts/#{account.id}/referrals/settings",
          params: { referral_settings: { referral_enabled: true } },
          headers: agent.create_new_auth_token, as: :json

      expect(response).to have_http_status(:unauthorized)
    end

    it 'allows admins to update referral settings' do
      put "/api/v1/accounts/#{account.id}/referrals/settings",
          params: { referral_settings: { referral_enabled: true } },
          headers: admin.create_new_auth_token, as: :json

      expect(response).to have_http_status(:success)
    end

    it 'still allows agents to list referrals' do
      get "/api/v1/accounts/#{account.id}/referrals",
          headers: agent.create_new_auth_token, as: :json

      expect(response).to have_http_status(:success)
    end
  end

  describe 'backup pages' do
    it 'blocks agents from creating backup pages' do
      post "/api/v1/accounts/#{account.id}/backup_pages",
           params: { platform: 'facebook', page_id: '123' },
           headers: agent.create_new_auth_token, as: :json

      expect(response).to have_http_status(:unauthorized)
    end

    it 'allows admins to create backup pages' do
      post "/api/v1/accounts/#{account.id}/backup_pages",
           params: { platform: 'facebook', page_id: '123' },
           headers: admin.create_new_auth_token, as: :json

      expect(response).to have_http_status(:created)
    end

    it 'never serializes access_token in JSON responses' do
      create(:backup_page, account: account, access_token: 'super_secret_fb_token')

      get "/api/v1/accounts/#{account.id}/backup_pages",
          headers: agent.create_new_auth_token, as: :json

      expect(response).to have_http_status(:success)
      expect(response.body).not_to include('super_secret_fb_token')
      expect(response.body).not_to include('access_token')
    end
  end

  describe 'cashier claims tenancy' do
    let(:other_account) { create(:account) }

    it 'does not expose another account claim' do
      inbox = create(:inbox, account: other_account)
      contact = create(:contact, account: other_account)
      conversation = create(:conversation, account: other_account, inbox: inbox, contact: contact)
      claim = create(:cashier_claim, account: other_account, conversation: conversation, contact: contact)

      post "/api/v1/accounts/#{account.id}/cashier_claims/#{claim.id}/claim",
           headers: admin.create_new_auth_token, as: :json

      expect(response).to have_http_status(:not_found)
      expect(claim.reload.status).to eq('pending')
    end
  end
end
