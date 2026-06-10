# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Super Admin Patra account control', type: :request do
  let!(:super_admin) { create(:super_admin) }
  let!(:account) { create(:account, name: 'Alpha Ops') }

  def enable_console_actions
    allow(Patra::AdminConsole).to receive(:actions_enabled?).and_return(true)
  end

  describe 'GET /super_admin/patra_accounts/:id' do
    it 'redirects unauthenticated users' do
      get "/super_admin/patra_accounts/#{account.id}"
      expect(response).to have_http_status(:redirect)
    end

    it 'renders the lifecycle panel read-only for a super admin' do
      sign_in(super_admin, scope: :super_admin)
      get "/super_admin/patra_accounts/#{account.id}"
      expect(response).to have_http_status(:success)
      expect(response.body).to include('Alpha Ops')
      expect(response.body).to include('Lifecycle (audited, reversible)')
      expect(response.body).to include('Console actions are')
    end
  end

  describe 'POST /super_admin/patra_accounts/:id/suspend' do
    it 'returns 403 when the actions kill-switch is off (default)' do
      sign_in(super_admin, scope: :super_admin)
      post "/super_admin/patra_accounts/#{account.id}/suspend", params: { reason: 'fraud' }
      expect(response).to have_http_status(:forbidden)
      expect(account.reload.status).to eq('active')
      expect(PatraAdminAuditLog.count).to eq(0)
    end

    it 'requires a reason' do
      enable_console_actions
      sign_in(super_admin, scope: :super_admin)
      post "/super_admin/patra_accounts/#{account.id}/suspend", params: { reason: '  ' }
      expect(response).to redirect_to("/super_admin/patra_accounts/#{account.id}")
      expect(account.reload.status).to eq('active')
      expect(PatraAdminAuditLog.count).to eq(0)
    end

    it 'flips the enum to suspended and writes an audit row' do
      enable_console_actions
      sign_in(super_admin, scope: :super_admin)
      post "/super_admin/patra_accounts/#{account.id}/suspend", params: { reason: 'chargeback fraud' }

      expect(account.reload.status).to eq('suspended')
      log = PatraAdminAuditLog.last
      expect(log.action).to eq('account.suspend')
      expect(log.target_type).to eq('Account')
      expect(log.target_id).to eq(account.id)
      expect(log.reason).to eq('chargeback fraud')
      expect(log.admin_user_id).to eq(super_admin.id)
      expect(log.metadata['from_status']).to eq('active')
    end

    it 'verifies the existing API enforcement blocks the suspended account (ADM7 cross-check)' do
      enable_console_actions
      sign_in(super_admin, scope: :super_admin)
      post "/super_admin/patra_accounts/#{account.id}/suspend", params: { reason: 'fraud' }

      agent = create(:user, account: account, role: :administrator)
      get "/api/v1/accounts/#{account.id}/conversations", headers: agent.create_new_auth_token
      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe 'POST /super_admin/patra_accounts/:id/reactivate' do
    before { account.suspended! }

    it 'reactivates with audit row' do
      enable_console_actions
      sign_in(super_admin, scope: :super_admin)
      post "/super_admin/patra_accounts/#{account.id}/reactivate", params: { reason: 'cleared review' }
      expect(account.reload.status).to eq('active')
      expect(PatraAdminAuditLog.last.action).to eq('account.reactivate')
    end

    it 'is blocked without the kill-switch' do
      sign_in(super_admin, scope: :super_admin)
      post "/super_admin/patra_accounts/#{account.id}/reactivate", params: { reason: 'x' }
      expect(response).to have_http_status(:forbidden)
      expect(account.reload.status).to eq('suspended')
    end
  end

  describe 'POST /super_admin/patra_accounts/:id/toggle_feature' do
    it 'toggles a known features.yml flag and audits from/to' do
      enable_console_actions
      sign_in(super_admin, scope: :super_admin)
      expect(account.feature_enabled?('patra_operator_console')).to be(false)

      post "/super_admin/patra_accounts/#{account.id}/toggle_feature",
           params: { feature: 'patra_operator_console', reason: 'pilot tenant' }

      expect(account.reload.feature_enabled?('patra_operator_console')).to be(true)
      log = PatraAdminAuditLog.last
      expect(log.action).to eq('account.feature_toggle')
      expect(log.metadata).to include('feature' => 'patra_operator_console', 'from' => false, 'to' => true)
    end

    it 'rejects unknown feature names' do
      enable_console_actions
      sign_in(super_admin, scope: :super_admin)
      post "/super_admin/patra_accounts/#{account.id}/toggle_feature",
           params: { feature: 'evil_flag', reason: 'x' }
      expect(response).to redirect_to("/super_admin/patra_accounts/#{account.id}")
      expect(PatraAdminAuditLog.count).to eq(0)
    end
  end
end
