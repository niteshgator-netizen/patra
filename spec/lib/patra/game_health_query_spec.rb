# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Patra::GameHealthQuery do
  before do
    unless ActiveRecord::Encryption.config.primary_key
      ActiveRecord::Encryption.configure(
        primary_key: 'patra-test-primary-key-000000000',
        deterministic_key: 'patra-test-deterministic-key-000',
        key_derivation_salt: 'patra-test-salt-0000000000000000',
        support_unencrypted_data: true
      )
    end
  end

  let!(:account_a) { create(:account, name: 'Alpha Ops') }
  let!(:account_b) { create(:account, name: 'Bravo Ops') }
  let!(:game_x) { Game.create!(name: 'Fire Kirin', slug: 'fire_kirin', sort_order: 1) }
  let!(:game_y) { Game.create!(name: 'Orion Stars', slug: 'orion_stars', sort_order: 2) }

  def connection(account, game, failure_count: 0, last_used_at: nil, **attrs)
    AgentGame.create!(account: account, game: game, status: 'inactive', credentials: { 'agent_secret' => 'raw-secret-value' },
                      failure_count: failure_count, last_used_at: last_used_at, **attrs)
  end

  describe '.health_status (replicates the API controller thresholds)' do
    it 'maps failure_count to down/degraded/healthy exactly like the cashier-facing endpoint' do
      expect(described_class.health_status(connection(account_a, game_x, failure_count: 3))).to eq('down')
      expect(described_class.health_status(connection(account_a, game_y, failure_count: 1))).to eq('degraded')
      expect(described_class.health_status(connection(account_b, game_x))).to eq('healthy')
    end
  end

  describe '.session_age_minutes' do
    it 'returns rounded minutes since last use, nil when never used' do
      ag = connection(account_a, game_x, last_used_at: 90.minutes.ago)
      expect(described_class.session_age_minutes(ag)).to be_within(1).of(90)
      expect(described_class.session_age_minutes(connection(account_a, game_y))).to be_nil
    end
  end

  describe '.matrix' do
    before do
      connection(account_a, game_x, failure_count: 5,
                                    last_connection_ok: false,
                                    last_connection_checked_at: 10.minutes.ago,
                                    last_connection_message: 'timeout reaching panel')
      connection(account_a, game_y, failure_count: 0)
      connection(account_b, game_y, failure_count: 1)
    end

    let(:matrix) { described_class.matrix }

    it 'builds rows per account with per-game cells' do
      row_a = matrix[:rows].find { |r| r[:account_id] == account_a.id }
      expect(row_a[:cells][game_x.id][:health]).to eq('down')
      expect(row_a[:cells][game_x.id][:last_error]).to eq('timeout reaching panel')
      expect(row_a[:cells][game_y.id][:health]).to eq('healthy')
      expect(row_a[:down_count]).to eq(1)
    end

    it 'sorts accounts with down connections first' do
      expect(matrix[:rows].first[:account_id]).to eq(account_a.id)
    end

    it 'summarizes per game and platform-wide' do
      expect(matrix[:down_total]).to eq(1)
      expect(matrix[:per_game_summary][game_x.id]).to include(down: 1, total: 1)
      expect(matrix[:per_game_summary][game_y.id]).to include(healthy: 1, degraded: 1, total: 2)
    end

    it '🔒 never exposes credentials anywhere in the matrix payload' do
      expect(matrix.to_json).not_to include('raw-secret-value')
      expect(matrix.to_json).not_to include('agent_secret')
    end
  end
end
