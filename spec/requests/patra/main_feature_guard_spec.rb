# frozen_string_literal: true

require 'rails_helper'

# Patra PHASE 5 — main-feature guard + owner-only grants.
# WALL-LOCAL-UNRUNNABLE: needs the granted_main_features migration applied + Rails boot.
# Run on the Render shell after deploy:
#   bundle exec rspec spec/requests/patra/main_feature_guard_spec.rb
RSpec.describe 'Patra main-feature grants', type: :request do
  let!(:account) { create(:account) }
  let!(:owner) { create(:user, account: account, role: :administrator) }                  # creator: inviter NULL, lowest id
  let!(:manager) { create(:user, account: account, role: :administrator, inviter: owner) } # non-owner admin (a "manager")
  let!(:support_role) { create(:custom_role, account: account, permissions: %w[view_all_inboxes contact_manage]) }
  let!(:support) { create(:user, account: account, role: :agent) }

  before { support_au.update!(custom_role: support_role) }

  def manager_au
    manager.account_users.find_by(account: account)
  end

  def support_au
    support.account_users.find_by(account: account)
  end

  describe 'main-feature guard on backup_pages#create' do
    let(:path) { "/api/v1/accounts/#{account.id}/backup_pages" }
    let(:params) { { platform: 'facebook', page_id: 'p1', page_name: 'Page', access_token: 'tok' } }

    it 'owner passes the guard' do
      post path, params: params, headers: owner.create_new_auth_token
      expect(response).not_to have_http_status(:forbidden)
    end

    it 'ungranted manager is denied (403)' do
      post path, params: params, headers: manager.create_new_auth_token
      expect(response).to have_http_status(:forbidden)
    end

    it 'granted manager passes the guard' do
      manager_au.update!(granted_main_features: ['backup_pages'])
      post path, params: params, headers: manager.create_new_auth_token
      expect(response).not_to have_http_status(:forbidden)
    end

    it 'manager granted a DIFFERENT feature is still denied' do
      manager_au.update!(granted_main_features: ['payment_handles'])
      post path, params: params, headers: manager.create_new_auth_token
      expect(response).to have_http_status(:forbidden)
    end

    it 'support is denied (403)' do
      post path, params: params, headers: support.create_new_auth_token
      expect(response).to have_http_status(:forbidden)
    end
  end

  describe 'MainFeatureGrantsController (owner-only)' do
    it 'lets the owner set whitelisted grants and drops unknown keys' do
      put "/api/v1/accounts/#{account.id}/main_feature_grants/#{manager_au.id}",
          params: { granted_main_features: %w[backup_pages bogus_key payment_handles] },
          headers: owner.create_new_auth_token
      expect(response).to have_http_status(:success)
      expect(manager_au.reload.granted_main_features).to contain_exactly('backup_pages', 'payment_handles')
    end

    it 'returns the current grants on show for the owner' do
      manager_au.update!(granted_main_features: ['roles'])
      get "/api/v1/accounts/#{account.id}/main_feature_grants/#{manager_au.id}",
          headers: owner.create_new_auth_token
      expect(response).to have_http_status(:success)
      expect(JSON.parse(response.body)['granted_main_features']).to eq(['roles'])
    end

    it 'forbids a non-owner manager from reading grants' do
      get "/api/v1/accounts/#{account.id}/main_feature_grants/#{manager_au.id}",
          headers: manager.create_new_auth_token
      expect(response).to have_http_status(:forbidden)
    end

    it 'forbids a non-owner manager from writing grants (no mutation)' do
      put "/api/v1/accounts/#{account.id}/main_feature_grants/#{manager_au.id}",
          params: { granted_main_features: ['roles'] },
          headers: manager.create_new_auth_token
      expect(response).to have_http_status(:forbidden)
      expect(manager_au.reload.granted_main_features).to eq([])
    end

    it 'forbids support from writing grants' do
      put "/api/v1/accounts/#{account.id}/main_feature_grants/#{support_au.id}",
          params: { granted_main_features: ['roles'] },
          headers: support.create_new_auth_token
      expect(response).to have_http_status(:forbidden)
    end
  end
end
