# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Super Admin Patra impersonation', type: :request do
  include ActiveSupport::Testing::TimeHelpers

  let!(:super_admin) { create(:super_admin) }
  let!(:other_super_admin) { create(:super_admin) }
  let!(:account) { create(:account) }
  let!(:target) { create(:user, account: account) }

  def enable_console_actions
    allow(Patra::AdminConsole).to receive(:actions_enabled?).and_return(true)
  end

  def start_impersonation(reason: 'support ticket #42')
    post '/super_admin/patra_impersonation', params: { user_id: target.id, reason: reason }
  end

  describe 'POST /super_admin/patra_impersonation (enter)' do
    it 'redirects unauthenticated users and writes nothing' do
      start_impersonation
      expect(response).to have_http_status(:redirect)
      expect(PatraAdminAuditLog.count).to eq(0)
    end

    it 'is 403 while the kill-switch is off (default)' do
      sign_in(super_admin, scope: :super_admin)
      start_impersonation
      expect(response).to have_http_status(:forbidden)
      expect(PatraAdminAuditLog.count).to eq(0)
    end

    it 'requires a reason' do
      enable_console_actions
      sign_in(super_admin, scope: :super_admin)
      start_impersonation(reason: '   ')
      expect(response).to have_http_status(:redirect)
      expect(PatraAdminAuditLog.count).to eq(0)
      expect(session['patra_impersonation']).to be_nil
    end

    it 'audits BEFORE the session starts and redirects to the one-time SSO login' do
      enable_console_actions
      sign_in(super_admin, scope: :super_admin)
      start_impersonation

      log = PatraAdminAuditLog.last
      expect(log.action).to eq('impersonation.start')
      expect(log.admin_user_id).to eq(super_admin.id)
      expect(log.target_id).to eq(target.id)
      expect(log.reason).to eq('support ticket #42')
      expect(log.ip_address).to be_present

      expect(response).to have_http_status(:redirect)
      expect(response.location).to include('/app/login')
      expect(response.location).to include('impersonation=true')

      marker = session['patra_impersonation']
      expect(marker['impersonator_id']).to eq(super_admin.id)
      expect(marker['target_user_id']).to eq(target.id)
      expect(Time.zone.parse(marker['expires_at'])).to be > 25.minutes.from_now
      expect(session[:impersonator_id]).to eq(super_admin.id)
    end

    it 'never logs the SSO token in the audit trail' do
      enable_console_actions
      sign_in(super_admin, scope: :super_admin)
      start_impersonation
      token = response.location[/sso_auth_token=([^&]+)/, 1]
      expect(token).to be_present
      expect(PatraAdminAuditLog.last.attributes.to_json).not_to include(token)
    end

    # SuperAdmin controllers don't include RequestExceptionHandler, and the
    # test env runs with action_dispatch.show_exceptions = true (upstream
    # Chatwoot default), so the RecordInvalid is RENDERED as a 422 response
    # instead of propagating to the spec. The contract is the same: the
    # request fails and no impersonation marker is written.
    it 'writes no marker and no start row when the audit insert fails (audit-first contract)' do
      enable_console_actions
      sign_in(super_admin, scope: :super_admin)
      allow(Patra::AdminAudit).to receive(:record).and_raise(ActiveRecord::RecordInvalid)

      start_impersonation
      expect(response).to have_http_status(:unprocessable_entity)
      expect(session['patra_impersonation']).to be_nil
      expect(PatraAdminAuditLog.count).to eq(0)
    end

    it 'refuses to impersonate a super admin and audits the refusal' do
      enable_console_actions
      sign_in(super_admin, scope: :super_admin)
      post '/super_admin/patra_impersonation', params: { user_id: other_super_admin.id, reason: 'nope' }

      expect(response).to have_http_status(:forbidden)
      expect(session['patra_impersonation']).to be_nil
      expect(PatraAdminAuditLog.last.action).to eq('impersonation.denied_super_admin_target')
    end
  end

  describe 'GET /super_admin/patra_impersonation (status contract for SPA banner)' do
    it 'reports inactive by default' do
      sign_in(super_admin, scope: :super_admin)
      get '/super_admin/patra_impersonation'
      expect(response.parsed_body['active']).to be(false)
      expect(response.headers['X-Patra-Impersonation']).to be_nil
    end

    it 'reports active with expiry, and stamps the response header' do
      enable_console_actions
      sign_in(super_admin, scope: :super_admin)
      start_impersonation

      get '/super_admin/patra_impersonation'
      body = response.parsed_body
      expect(body['active']).to be(true)
      expect(body['target_user_id']).to eq(target.id)
      expect(body['expires_at']).to be_present
      expect(response.headers['X-Patra-Impersonation']).to include('active')
      expect(response.headers['X-Patra-Impersonation']).to include("target_user_id=#{target.id}")
    end
  end

  describe 'DELETE /super_admin/patra_impersonation (exit)' do
    it 'audits the exit with duration and clears the marker, even with the kill-switch off' do
      enable_console_actions
      sign_in(super_admin, scope: :super_admin)
      start_impersonation

      allow(Patra::AdminConsole).to receive(:actions_enabled?).and_return(false)
      delete '/super_admin/patra_impersonation'

      expect(response).to redirect_to('/super_admin')
      log = PatraAdminAuditLog.last
      expect(log.action).to eq('impersonation.exit')
      expect(log.metadata).to have_key('duration_seconds')
      expect(session['patra_impersonation']).to be_nil
      expect(session[:impersonator_id]).to be_nil
    end
  end

  describe 'time-box auto-exit' do
    it 'expires the marker on the next console request after 30 minutes and audits it' do
      enable_console_actions
      sign_in(super_admin, scope: :super_admin)
      start_impersonation
      expect(session['patra_impersonation']).to be_present

      travel 31.minutes do
        get '/super_admin/patra_impersonation'
        expect(response.parsed_body['active']).to be(false)
        expect(session['patra_impersonation']).to be_nil
        expect(PatraAdminAuditLog.where(action: 'impersonation.auto_exit').count).to eq(1)
        expect(response.headers['X-Patra-Impersonation']).to be_nil
      end
    end

    it 'treats a corrupted expiry as expired (no unbounded sessions)' do
      enable_console_actions
      sign_in(super_admin, scope: :super_admin)
      start_impersonation

      # Corrupt the marker through a fresh start with a stubbed clock instead
      # of poking the session store: stub parse failure path.
      allow(Time.zone).to receive(:parse).and_raise(ArgumentError)
      get '/super_admin/patra_impersonation'
      expect(session['patra_impersonation']).to be_nil
    end
  end
end
