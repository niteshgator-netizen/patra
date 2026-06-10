# frozen_string_literal: true

# The dollars ride this code: audit logging, idempotency, guards, failover.
# The game client is fully mocked — no panel is ever touched.
require 'rails_helper'

RSpec.describe Games::ActionExecutor do
  let(:account) { create(:account) }
  let(:game) { create(:game, slug: 'game_vault', name: 'Game Vault') }
  let(:agent_game) { create(:agent_game, account: account, game: game) }
  let(:contact) { create(:contact, account: account) }

  let(:client) do
    double('GameClient',
           get_user_id: { 'data' => { 'user_id' => '777' } },
           recharge: { 'code' => 0, 'msg' => 'Success', 'data' => {} },
           withdraw: { 'code' => 0, 'msg' => 'Success', 'data' => {} })
  end

  let(:executor) { described_class.new(agent_game: agent_game, contact: contact) }

  before do
    allow(Games::ClientRegistry).to receive(:client_for).and_return(client)
    allow(Games::TelegramNotifier).to receive(:low_balance_alert)
    allow(Approvals::CashoutApprovalGate).to receive(:requires_approval?).and_return(false)
    allow(Contacts::BlacklistChecker).to receive(:blacklisted?).and_return(false)
  end

  describe '#load_player' do
    it 'audits a successful load and resets panel failures' do
      agent_game.update!(failure_count: 2)

      result = executor.load_player(game_username: 'player1', amount: 25.0)

      expect(result[:ok]).to be true
      action = result[:action].reload
      expect(action.status).to eq('success')
      expect(action.action_type).to eq('load')
      expect(action.amount).to eq(25.0)
      expect(action.game_user_id).to eq('777')
      expect(agent_game.reload.failure_count).to eq(0)
      expect(agent_game.last_used_at).to be_present
    end

    it 'raises IdempotencyError when the order_id was already used' do
      create(:game_action, account: account, agent_game: agent_game, order_id: 'dup_1')

      expect do
        executor.load_player(game_username: 'player1', amount: 25.0, order_id: 'dup_1')
      end.to raise_error(described_class::IdempotencyError)
      expect(client).not_to have_received(:recharge)
    end

    it 'returns a structured failure (never nil) when the client raises a typed error' do
      allow(client).to receive(:recharge)
        .and_raise(Games::ClientError.new('panel maintenance', code: 18, payload: { 'code' => 18 }))

      result = executor.load_player(game_username: 'player1', amount: 25.0)

      expect(result[:ok]).to be false
      expect(result[:code]).to eq(18)
      expect(result[:error]).to eq('panel maintenance')
      action = result[:action].reload
      expect(action.status).to eq('failed')
      expect(action.api_response_code.to_s).to eq('18')
      expect(agent_game.reload.failure_count).to eq(1)
    end

    it 'returns a structured failure with code -1 on unexpected errors' do
      allow(client).to receive(:get_user_id).and_raise(StandardError, 'socket hang up')

      result = executor.load_player(game_username: 'player1', amount: 25.0)

      expect(result[:ok]).to be false
      expect(result[:code]).to eq(-1)
      expect(result[:action].reload.status).to eq('failed')
    end

    it 'fails the action when the player cannot be resolved' do
      allow(client).to receive(:get_user_id).and_return({ 'data' => {} })

      result = executor.load_player(game_username: 'ghost', amount: 25.0)

      expect(result[:ok]).to be false
      expect(result[:error]).to match(/Could not find player ID/)
    end

    it 'blocks blacklisted contacts before touching the panel' do
      allow(Contacts::BlacklistChecker).to receive(:blacklisted?).and_return(true)

      result = executor.load_player(game_username: 'player1', amount: 25.0)

      expect(result[:ok]).to be false
      expect(result[:code]).to eq('blacklisted')
      expect(GameAction.count).to eq(0)
    end

    it 'enforces the per-panel max_load_amount credential' do
      agent_game.update!(credentials: agent_game.credentials.merge('max_load_amount' => '50'))

      result = executor.load_player(game_username: 'player1', amount: 51.0)

      expect(result[:ok]).to be false
      expect(result[:error]).to match(/exceeds max \$50/)
      expect(GameAction.count).to eq(0)
    end
  end

  describe '#cashout_player' do
    it 'audits a successful cashout' do
      result = executor.cashout_player(game_username: 'player1', amount: 40.0)

      expect(result[:ok]).to be true
      expect(result[:action].reload.action_type).to eq('cashout')
    end

    it 'stops at the approval gate without calling the panel' do
      allow(Approvals::CashoutApprovalGate).to receive(:requires_approval?).and_return(true)
      allow(Approvals::CashoutApprovalGate).to receive(:create_request!)
        .and_return(instance_double(ApprovalRequest, id: 9))

      result = executor.cashout_player(game_username: 'player1', amount: 500.0)

      expect(result[:ok]).to be false
      expect(result[:code]).to eq('approval_required')
      expect(result[:approval_request_id]).to eq(9)
      expect(GameAction.count).to eq(0)
    end

    it 'skips the gate only when skip_approval_gate is passed (post-approval resume)' do
      allow(Approvals::CashoutApprovalGate).to receive(:requires_approval?).and_return(true)

      result = executor.cashout_player(game_username: 'player1', amount: 500.0, skip_approval_gate: true)

      expect(result[:ok]).to be true
      expect(Approvals::CashoutApprovalGate).not_to have_received(:requires_approval?)
    end

    it 'enforces max_cashout_amount' do
      agent_game.update!(credentials: agent_game.credentials.merge('max_cashout_amount' => '100'))

      result = executor.cashout_player(game_username: 'player1', amount: 101.0)

      expect(result[:ok]).to be false
      expect(result[:error]).to match(/exceeds max/)
    end
  end

  describe '#add_player' do
    before do
      allow(client).to receive(:add_user).and_return({ 'code' => 0, 'msg' => 'Success' })
      allow(executor).to receive(:sleep) # no real 1s wait in tests
    end

    it 'verifies the account really exists and returns the password' do
      result = executor.add_player(game_username: 'newbie', password: 'pass1234')

      expect(result[:ok]).to be true
      expect(result[:password]).to eq('pass1234')
    end

    it 'flags a silent fail when creation says OK but the player does not exist' do
      allow(client).to receive(:get_user_id).and_return(
        { 'data' => { 'user_id' => nil } } # verification lookup finds nothing
      )

      result = executor.add_player(game_username: 'ghost', password: 'pass1234')

      expect(result[:ok]).to be false
      expect(result[:code]).to eq('silent_fail')
      expect(result[:action].reload.status).to eq('failed')
      expect(agent_game.reload.failure_count).to eq(1)
    end

    it 'reuses a verified existing account on a documented already-exists code (shared namespace)' do
      allow(client).to receive(:already_exists_code?) { |code| code.to_i == 20 }
      allow(client).to receive(:add_user)
        .and_raise(Games::ClientError.new('Account already exists', code: 20))

      result = executor.add_player(game_username: 'existing_gv_player', password: 'pass1234')

      expect(result[:ok]).to be true
      expect(result[:reused_existing]).to be true
      expect(result[:action].reload.status).to eq('success')
      expect(result[:action].metadata['reused_existing']).to be true
    end

    it 'keeps the failure when the client does not document an already-exists code' do
      # the base double has no already_exists_code? stub → respond_to? is false → no reuse path
      allow(client).to receive(:add_user)
        .and_raise(Games::ClientError.new('Account already exists', code: 20))

      result = executor.add_player(game_username: 'existing', password: 'pass1234')

      expect(result[:ok]).to be false
      expect(result[:code]).to eq(20)
    end
  end

  describe '#check_player_balance' do
    it 'returns the balance for a resolvable player' do
      allow(client).to receive(:user_balance).and_return({ 'data' => { 'user_balance' => '42.5' } })

      expect(executor.check_player_balance(game_username: 'player1')).to eq('42.5')
    end

    it 'returns nil when the player cannot be resolved' do
      allow(client).to receive(:get_user_id).and_return({ 'data' => {} })

      expect(executor.check_player_balance(game_username: 'ghost')).to be_nil
    end
  end

  describe 'low agent balance alert' do
    it 'fires telegram when the panel balance drops below the configured threshold' do
      agent_game.update!(credentials: agent_game.credentials.merge('low_balance_threshold' => '100'))
      allow(client).to receive(:recharge).and_return(
        { 'code' => 0, 'msg' => 'Success', 'data' => { 'agent_balance' => '60.0' } }
      )

      executor.load_player(game_username: 'player1', amount: 25.0)

      expect(Games::TelegramNotifier).to have_received(:low_balance_alert)
        .with(hash_including(balance: 60.0, threshold: 100))
    end
  end
end
