# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Patra::AdminAudit do
  let(:super_admin) { create(:super_admin) }
  let(:account) { create(:account) }
  let(:fake_request) { instance_double(ActionDispatch::Request, remote_ip: '203.0.113.9') }

  describe '.record' do
    it 'writes an append-only row with admin, action, target, reason and ip' do
      log = described_class.record(
        admin: super_admin,
        action: 'account.suspend',
        target: account,
        reason: 'fraud review',
        metadata: { from_status: 'active' },
        request: fake_request
      )

      expect(log).to be_persisted
      expect(log.admin_user_id).to eq(super_admin.id)
      expect(log.action).to eq('account.suspend')
      expect(log.target_type).to eq('Account')
      expect(log.target_id).to eq(account.id)
      expect(log.reason).to eq('fraud review')
      expect(log.metadata).to eq('from_status' => 'active')
      expect(log.ip_address).to eq('203.0.113.9')
    end

    it 'stores the base class for STI targets (SuperAdmin -> User)' do
      log = described_class.record(admin: super_admin, action: 'noop', target: super_admin)
      expect(log.target_type).to eq('User')
    end

    it 'works without target, reason, metadata or request' do
      log = described_class.record(admin: super_admin, action: 'console.viewed')
      expect(log).to be_persisted
      expect(log.target_type).to be_nil
      expect(log.ip_address).to be_nil
      expect(log.metadata).to eq({})
    end

    it 'raises (and writes nothing) when action is blank, so callers abort' do
      expect do
        described_class.record(admin: super_admin, action: '')
      end.to raise_error(ActiveRecord::RecordInvalid)
      expect(PatraAdminAuditLog.count).to eq(0)
    end

    it 'scrubs credential-shaped metadata before persisting' do
      log = described_class.record(
        admin: super_admin,
        action: 'agent_game.inspect',
        metadata: {
          password: 'hunter2',
          api_key: 'abc',
          nested: { 'AuthToken' => 'tok', safe: 'visible' },
          list: [{ secret: 'x' }, 'plain'],
          looks_like_a_key: 'A1b2C3d4E5f6G7h8I9j0K1l2M3n4O5p6',
          note: 'short and harmless'
        }
      )

      expect(log.metadata['password']).to eq('[SCRUBBED]')
      expect(log.metadata['api_key']).to eq('[SCRUBBED]')
      expect(log.metadata['nested']['AuthToken']).to eq('[SCRUBBED]')
      expect(log.metadata['nested']['safe']).to eq('visible')
      expect(log.metadata['list'][0]['secret']).to eq('[SCRUBBED]')
      expect(log.metadata['list'][1]).to eq('plain')
      expect(log.metadata['looks_like_a_key']).to eq('[SCRUBBED]')
      expect(log.metadata['note']).to eq('short and harmless')
    end
  end

  describe 'immutability (append-only contract)' do
    let!(:log) { described_class.record(admin: super_admin, action: 'account.suspend', target: account) }

    it 'rejects updates after persist' do
      expect { log.update!(reason: 'tampered') }.to raise_error(ActiveRecord::ReadOnlyRecord)
      expect(log.reload.reason).to be_nil
    end

    it 'rejects destroy' do
      expect { log.destroy! }.to raise_error(ActiveRecord::ReadOnlyRecord)
      expect(PatraAdminAuditLog.exists?(log.id)).to be(true)
    end
  end
end
