# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Super Admin Patra command center', type: :request do
  let!(:super_admin) { create(:super_admin) }
  let!(:account_a) { create(:account, name: 'Alpha Ops') }
  let!(:account_b) { create(:account, name: 'Bravo Ops') }
  let!(:account_c) { create(:account, name: 'Charlie Ops', status: :suspended) }

  before do
    create(:contact, account: account_a, custom_attributes: {
             'patra_finance_logs' => [
               { 'kind' => 'deposit', 'amount' => 100.0, 'logged_at' => 2.days.ago.iso8601 },
               'malformed-entry'
             ]
           })
  end

  describe 'GET /super_admin/patra_dashboard' do
    it 'redirects unauthenticated users' do
      get '/super_admin/patra_dashboard'
      expect(response).to have_http_status(:redirect)
    end

    it 'renders the command center with accounts, money and billing panels' do
      sign_in(super_admin, scope: :super_admin)
      get '/super_admin/patra_dashboard'
      expect(response).to have_http_status(:success)
      expect(response.body).to include('Patra Command Center')
      expect(response.body).to include('This panel activates automatically')
      expect(response.body).to include('malformed finance entry skipped')
      expect(response.body).to include('Alpha Ops') # top account by net
    end

    it 'accepts a quick range param' do
      sign_in(super_admin, scope: :super_admin)
      get '/super_admin/patra_dashboard', params: { days: 7 }
      expect(response).to have_http_status(:success)
    end

    it 'accepts a custom from/to range and ignores garbage dates' do
      sign_in(super_admin, scope: :super_admin)
      get '/super_admin/patra_dashboard', params: { from: 10.days.ago.to_date.to_s, to: Time.zone.today.to_s }
      expect(response).to have_http_status(:success)
      get '/super_admin/patra_dashboard', params: { from: 'garbage', to: 'junk' }
      expect(response).to have_http_status(:success)
    end

    it 'keeps the legacy JSON contract' do
      sign_in(super_admin, scope: :super_admin)
      get '/super_admin/patra_dashboard.json'
      expect(response).to have_http_status(:success)
      body = response.parsed_body
      expect(body['total_accounts']).to eq(Account.count)
      expect(body).to have_key('sidekiq_queue_depth')
    end
  end
end
