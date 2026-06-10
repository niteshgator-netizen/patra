# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Super Admin platform banners (audited)', type: :request do
  let!(:super_admin) { create(:super_admin) }

  context 'when not on chatwoot cloud' do
    it 'is not found (existing gate preserved)' do
      allow(ChatwootApp).to receive(:chatwoot_cloud?).and_return(false)
      sign_in(super_admin, scope: :super_admin)
      expect do
        get '/super_admin/platform_banners'
      end.to raise_error(ActionController::RoutingError)
    end
  end

  context 'when on chatwoot cloud' do
    before do
      allow(ChatwootApp).to receive(:chatwoot_cloud?).and_return(true)
      sign_in(super_admin, scope: :super_admin)
    end

    it 'audits banner creation with the message excerpt' do
      post '/super_admin/platform_banners',
           params: { platform_banner: { banner_message: 'Maintenance at midnight UTC', banner_type: 'warning', active: true } }

      banner = PlatformBanner.last
      expect(banner.banner_message).to eq('Maintenance at midnight UTC')

      log = PatraAdminAuditLog.last
      expect(log.action).to eq('platform_banner.create')
      expect(log.admin_user_id).to eq(super_admin.id)
      expect(log.reason).to include('Maintenance at midnight')
      expect(log.metadata['attributes']).to include('banner_type' => 'warning')
    end

    it 'audits banner update with target deep-link data' do
      banner = PlatformBanner.create!(banner_message: 'old', banner_type: 'info')
      put "/super_admin/platform_banners/#{banner.id}",
          params: { platform_banner: { banner_message: 'new text', banner_type: 'info', active: false } }

      log = PatraAdminAuditLog.last
      expect(log.action).to eq('platform_banner.update')
      expect(log.target_type).to eq('PlatformBanner')
      expect(log.target_id).to eq(banner.id)
    end

    it 'audits banner destroy' do
      banner = PlatformBanner.create!(banner_message: 'bye', banner_type: 'info')
      delete "/super_admin/platform_banners/#{banner.id}"

      log = PatraAdminAuditLog.last
      expect(log.action).to eq('platform_banner.destroy')
      expect(log.target_id).to eq(banner.id)
      expect(PlatformBanner.exists?(banner.id)).to be(false)
    end
  end

  describe 'tenant-side read path (confirms end-to-end banner delivery)' do
    it 'exposes active banners in app config only on cloud' do
      allow(ChatwootApp).to receive(:chatwoot_cloud?).and_return(true)
      PlatformBanner.create!(banner_message: 'Visible to tenants', banner_type: 'info', active: true)
      PlatformBanner.create!(banner_message: 'Inactive hidden', banner_type: 'info', active: false)

      get '/'
      expect(response.body).to include('Visible to tenants')
      expect(response.body).not_to include('Inactive hidden')
    end
  end
end
