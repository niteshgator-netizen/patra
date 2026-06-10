# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Patra::FinanceAnalytics do
  let(:range) { 30.days.ago.beginning_of_day..Time.zone.now.end_of_day }

  let!(:account_a) { create(:account, name: 'Alpha Ops') }
  let!(:account_b) { create(:account, name: 'Bravo Ops') }
  let!(:account_c) { create(:account, name: 'Charlie Ops') }

  def finance_contact(account, entries)
    create(:contact, account: account, custom_attributes: { 'patra_finance_logs' => entries })
  end

  describe '.platform_scan' do
    before do
      finance_contact(account_a, [
                        { 'kind' => 'deposit', 'amount' => 100.0, 'logged_at' => 2.days.ago.iso8601 },
                        { 'kind' => 'cashout', 'amount' => 40.0, 'logged_at' => 1.day.ago.iso8601 },
                        # out of range — ignored, not malformed
                        { 'kind' => 'deposit', 'amount' => 999.0, 'logged_at' => 90.days.ago.iso8601 },
                        # malformed: not a hash
                        'corrupted-string-entry',
                        # malformed: deposit with unparseable amount
                        { 'kind' => 'deposit', 'amount' => '??', 'logged_at' => 1.day.ago.iso8601 },
                        # malformed: deposit with unparseable time
                        { 'kind' => 'deposit', 'amount' => 10.0, 'logged_at' => 'not-a-time' },
                        # screenshot/status row — normal, ignored silently
                        { 'status' => 'Email Verified', 'amount' => '20', 'platform' => 'cashapp' }
                      ])
      finance_contact(account_a, [
                        { 'kind' => 'deposit', 'amount' => '$25.50', 'logged_at' => 3.days.ago.iso8601,
                          'flag_reason' => 'duplicate screenshot' }
                      ])
      finance_contact(account_b, [
                        { 'kind' => 'deposit', 'amount' => 50.0, 'logged_at' => 4.days.ago.iso8601 },
                        { 'kind' => 'flagged', 'amount' => 5.0, 'logged_at' => 4.days.ago.iso8601 }
                      ])
      # account_c: no finance contacts at all
    end

    let(:result) { described_class.platform_scan(range: range) }

    it 'totals deposits and cashouts across all accounts, in range only' do
      expect(result[:deposits][:count]).to eq(3) # 100 + 25.50 + 50
      expect(result[:deposits][:total]).to eq(175.5)
      expect(result[:cashouts][:count]).to eq(1)
      expect(result[:cashouts][:total]).to eq(40.0)
      expect(result[:net]).to eq(135.5)
    end

    it 'skips and counts malformed entries without raising' do
      expect(result[:malformed_count]).to eq(3)
    end

    it 'builds by-day rows sorted ascending with per-day net' do
      days = result[:by_day].map { |r| r[:date] }
      expect(days).to eq(days.sort)
      one_day_ago = result[:by_day].find { |r| r[:date] == 1.day.ago.to_date }
      expect(one_day_ago[:cashouts]).to eq(40.0)
    end

    it 'ranks top accounts by net with names' do
      top = result[:top_accounts]
      expect(top.first[:account_id]).to eq(account_a.id)
      expect(top.first[:name]).to eq('Alpha Ops')
      expect(top.first[:net]).to eq(85.5) # 125.5 deposits - 40 cashouts
      expect(top.map { |r| r[:account_id] }).not_to include(account_c.id)
    end

    it 'counts flagged players per account (flag_reason or kind=flagged)' do
      expect(result[:risk][:flagged_players_total]).to eq(2)
      expect(result[:risk][:accounts_with_flagged]).to eq(2)
      expect(result[:risk][:per_account][account_a.id]).to eq(1)
      expect(result[:risk][:per_account][account_b.id]).to eq(1)
    end
  end

  describe '.account_scan' do
    before do
      finance_contact(account_a, [{ 'kind' => 'deposit', 'amount' => 100.0, 'logged_at' => 2.days.ago.iso8601 }])
      finance_contact(account_b, [{ 'kind' => 'deposit', 'amount' => 70.0, 'logged_at' => 2.days.ago.iso8601 }])
    end

    it 'scopes the scan to one account' do
      result = described_class.account_scan(account_id: account_a.id, range: range)
      expect(result[:deposits][:total]).to eq(100.0)
      expect(result[:scanned_contacts]).to eq(1)
    end
  end

  describe 'by-game money via GameAction' do
    before do
      unless ActiveRecord::Encryption.config.primary_key
        ActiveRecord::Encryption.configure(
          primary_key: 'patra-test-primary-key-000000000',
          deterministic_key: 'patra-test-deterministic-key-000',
          key_derivation_salt: 'patra-test-salt-0000000000000000',
          support_unencrypted_data: true
        )
      end
      game = Game.create!(name: 'Fire Kirin', slug: 'fire_kirin')
      agent_game = AgentGame.create!(account: account_a, game: game, status: 'inactive', credentials: {})
      GameAction.create!(account: account_a, agent_game: agent_game, action_type: 'load', status: 'success',
                         amount: 80.0, order_id: 'ord_load_1')
      GameAction.create!(account: account_a, agent_game: agent_game, action_type: 'cashout', status: 'success',
                         amount: 30.0, order_id: 'ord_cash_1')
      GameAction.create!(account: account_a, agent_game: agent_game, action_type: 'load', status: 'failed',
                         amount: 500.0, order_id: 'ord_fail_1')
    end

    it 'aggregates successful loads/cashouts per game via SQL' do
      result = described_class.platform_scan(range: range)
      row = result[:by_game].find { |r| r[:game] == 'Fire Kirin' }
      expect(row[:loads_total]).to eq(80.0)
      expect(row[:loads_count]).to eq(1)
      expect(row[:cashouts_total]).to eq(30.0)
      expect(row[:net]).to eq(50.0)
    end
  end
end
