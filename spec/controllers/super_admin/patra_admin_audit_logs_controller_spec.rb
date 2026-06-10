# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Super Admin Patra audit logs', type: :request do
  let!(:super_admin) { create(:super_admin) }
  let!(:account) { create(:account) }
  let!(:older) do
    Patra::AdminAudit.record(admin: super_admin, action: 'account.reactivate', target: account, reason: 'all clear')
  end
  let!(:newer) do
    Patra::AdminAudit.record(admin: super_admin, action: 'account.suspend', target: account, reason: 'fraud review')
  end

  describe 'GET /super_admin/patra_admin_audit_logs' do
    it 'redirects unauthenticated users' do
      get '/super_admin/patra_admin_audit_logs'
      expect(response).to have_http_status(:redirect)
    end

    it 'lists audit rows newest-first for a super admin' do
      sign_in(super_admin, scope: :super_admin)
      get '/super_admin/patra_admin_audit_logs'
      expect(response).to have_http_status(:success)
      expect(response.body).to include('account.suspend')
      expect(response.body).to include('account.reactivate')
      expect(response.body.index('account.suspend')).to be < response.body.index('account.reactivate')
    end
  end

  describe 'GET /super_admin/patra_admin_audit_logs/:id' do
    it 'shows a single audit row' do
      sign_in(super_admin, scope: :super_admin)
      get "/super_admin/patra_admin_audit_logs/#{newer.id}"
      expect(response).to have_http_status(:success)
      expect(response.body).to include('fraud review')
    end
  end

  describe 'mutation surface' do
    it 'exposes no create/update/destroy routes' do
      sign_in(super_admin, scope: :super_admin)
      expect { post '/super_admin/patra_admin_audit_logs' }.to raise_error(ActionController::RoutingError)
      expect { put "/super_admin/patra_admin_audit_logs/#{newer.id}" }.to raise_error(ActionController::RoutingError)
      expect { delete "/super_admin/patra_admin_audit_logs/#{newer.id}" }.to raise_error(ActionController::RoutingError)
    end
  end
end
