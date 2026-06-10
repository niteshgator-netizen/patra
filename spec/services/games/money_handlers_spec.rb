# frozen_string_literal: true

# Money-path specs for the four orchestrator money handlers + fraud guards.
# The orchestrator is a HOT file: these specs READ its behavior, never change it.
# Every external interaction (game API via ActionExecutor, Telegram, DeepSeek)
# is mocked — no real side effects.
require 'rails_helper'

RSpec.describe Games::ConversationOrchestrator do
  let(:account) { create(:account) }
  let(:inbox) { create(:inbox, account: account) }
  let(:contact) { create(:contact, account: account) }
  let(:conversation) { create(:conversation, account: account, inbox: inbox, contact: contact) }

  let(:source_game) { create(:game, name: 'Game Vault', slug: 'game_vault') }
  let(:target_game) { create(:game, name: 'Juwa', slug: 'juwa') }
  let(:source_ag) { create(:agent_game, account: account, game: source_game) }
  let(:target_ag) { create(:agent_game, account: account, game: target_game) }

  let(:source_executor) { instance_double(Games::ActionExecutor) }
  let(:target_executor) { instance_double(Games::ActionExecutor) }

  let(:orchestrator) do
    described_class.new(account: account, contact: contact, conversation: conversation, messages: [])
  end

  before do
    # No real Telegram, ever.
    allow(Games::TelegramNotifier).to receive(:human_escalation)
    allow(Games::TelegramNotifier).to receive(:load_failed)
    allow(Games::TelegramNotifier).to receive(:cashout_alert)
    # No real DeepSeek — transfer-plan extraction falls back to regex (or is stubbed).
    allow(Ai::DeepseekClient).to receive(:complete).and_return(nil) if defined?(Ai::DeepseekClient)

    allow(Games::ActionExecutor).to receive(:new)
      .with(hash_including(agent_game: source_ag)).and_return(source_executor)
    allow(Games::ActionExecutor).to receive(:new)
      .with(hash_including(agent_game: target_ag)).and_return(target_executor)

    allow(orchestrator).to receive(:pick_agent_game) do |slug|
      { 'game_vault' => source_ag, 'juwa' => target_ag }[slug]
    end
    allow(orchestrator).to receive(:find_game_username_for_slug) do |_contact, slug|
      { 'game_vault' => 'gv_player', 'juwa' => 'juwa_player' }[slug]
    end
  end

  def stub_customer_text(text)
    allow(orchestrator).to receive(:latest_customer_text).and_return(text)
    allow(orchestrator).to receive(:recent_customer_text).and_return(text)
  end

  def stub_transfer_plan(source_slug:, loads:)
    allow(orchestrator).to receive(:extract_transfer_plan).and_return(
      { source_text: source_slug, source_slug: source_slug, cashout_amount: nil, loads: loads }
    )
  end

  describe '#handle_transfer_between_games' do
    before { stub_customer_text('move my money from game vault to juwa') }

    context 'velocity guard' do
      it 'escalates and moves no money when the cashout velocity threshold is hit' do
        create_list(:game_action, 3, account: account, agent_game: source_ag, contact: contact,
                                     action_type: 'cashout', status: 'success', amount: 10.0)
        stub_transfer_plan(source_slug: 'game_vault', loads: [{ game_slug: 'juwa', amount: 20.0 }])

        result = orchestrator.send(:handle_transfer_between_games, {})

        expect(result[:labels]).to include('velocity-flag')
        # velocity guard fires before any executor is even built — no game API touched
        expect(Games::ActionExecutor).not_to have_received(:new)
        expect(Games::TelegramNotifier).to have_received(:human_escalation)
          .with(hash_including(reason: a_string_matching(/VELOCITY FLAG/)))
      end
    end

    context 'normal cashout fork (balance >= cashout_min)' do
      before do
        allow(source_executor).to receive(:check_player_balance).and_return(100.0)
      end

      it 'rejects source == target' do
        stub_transfer_plan(source_slug: 'game_vault', loads: [{ game_slug: 'game_vault', amount: 20.0 }])

        result = orchestrator.send(:handle_transfer_between_games, {})

        expect(result[:labels]).to include('transfer-same-game')
      end

      it 'refuses to move more than the balance (over-amount guard)' do
        stub_transfer_plan(source_slug: 'game_vault', loads: [{ game_slug: 'juwa', amount: 150.0 }])
        allow(source_executor).to receive(:cashout_player)

        result = orchestrator.send(:handle_transfer_between_games, {})

        expect(result[:labels]).to include('transfer-short')
        expect(source_executor).not_to have_received(:cashout_player)
      end

      it 'cashes out the requested amount and loads the target on success' do
        stub_transfer_plan(source_slug: 'game_vault', loads: [{ game_slug: 'juwa', amount: 40.0 }])
        allow(source_executor).to receive(:cashout_player)
          .with(hash_including(game_username: 'gv_player', amount: 40.0))
          .and_return({ ok: true })
        allow(target_executor).to receive(:load_player)
          .with(hash_including(game_username: 'juwa_player', amount: 40.0))
          .and_return({ ok: true })

        result = orchestrator.send(:handle_transfer_between_games, {})

        expect(result[:labels]).to include('transfer-complete')
        expect(target_executor).to have_received(:load_player).once
      end

      it 'does not attempt any load when the source cashout fails' do
        stub_transfer_plan(source_slug: 'game_vault', loads: [{ game_slug: 'juwa', amount: 40.0 }])
        allow(source_executor).to receive(:cashout_player)
          .and_return({ ok: false, error: 'panel down', code: 5 })
        allow(target_executor).to receive(:load_player)

        result = orchestrator.send(:handle_transfer_between_games, {})

        expect(result[:labels]).to include('transfer-failed')
        expect(target_executor).not_to have_received(:load_player)
        expect(Games::TelegramNotifier).to have_received(:human_escalation)
          .with(hash_including(reason: a_string_matching(/No money moved/)))
      end

      it 'counts only successful loads and reports the remaining funds' do
        second_game = create(:game, name: 'Vblink', slug: 'vblink')
        second_ag = create(:agent_game, account: account, game: second_game)
        second_executor = instance_double(Games::ActionExecutor)
        allow(Games::ActionExecutor).to receive(:new)
          .with(hash_including(agent_game: second_ag)).and_return(second_executor)
        allow(orchestrator).to receive(:pick_agent_game) do |slug|
          { 'game_vault' => source_ag, 'juwa' => target_ag, 'vblink' => second_ag }[slug]
        end
        allow(orchestrator).to receive(:find_game_username_for_slug) do |_c, slug|
          { 'game_vault' => 'gv_player', 'juwa' => 'juwa_player', 'vblink' => 'vb_player' }[slug]
        end
        stub_transfer_plan(source_slug: 'game_vault',
                           loads: [{ game_slug: 'juwa', amount: 30.0 }, { game_slug: 'vblink', amount: 30.0 }])

        allow(source_executor).to receive(:cashout_player).and_return({ ok: true })
        allow(target_executor).to receive(:load_player).and_return({ ok: true })
        allow(second_executor).to receive(:load_player).and_return({ ok: false, error: 'maintenance', code: 21 })

        result = orchestrator.send(:handle_transfer_between_games, {})

        expect(result[:reply]).to match(/\$30/) # loaded juwa
        expect(result[:labels]).to include('transfer-partial')
        expect(result[:labels]).to include('needs-human')
        expect(Games::TelegramNotifier).to have_received(:human_escalation)
          .with(hash_including(reason: a_string_matching(/FAILED.*vblink|FAILED.*Vblink/i)))
      end
    end

    context 'deposit_only fork (balance below cashout_min)' do
      before do
        ReplyPreference.for_account(account.id).update!(transfer_mode: 'deposit_only')
        allow(source_executor).to receive(:check_player_balance).and_return(8.0)
        stub_transfer_plan(source_slug: 'game_vault', loads: [{ game_slug: 'juwa', amount: 8.0 }])
      end

      it 'moves the most recent successful non-freeplay deposit on the SOURCE game' do
        create(:game_action, account: account, agent_game: source_ag, contact: contact,
                             action_type: 'load', status: 'success', amount: 5.0,
                             created_at: 2.days.ago)
        create(:game_action, account: account, agent_game: source_ag, contact: contact,
                             action_type: 'load', status: 'success', amount: 6.0,
                             created_at: 1.day.ago)
        # freeplay load is NOT a deposit — must be skipped even though it is most recent
        create(:game_action, account: account, agent_game: source_ag, contact: contact,
                             action_type: 'load', status: 'success', amount: 7.0,
                             metadata: { 'freeplay' => 'true' }, created_at: 1.hour.ago)

        expect(source_executor).to receive(:cashout_player)
          .with(hash_including(amount: 6.0)).and_return({ ok: true })
        allow(target_executor).to receive(:load_player).and_return({ ok: true })

        orchestrator.send(:handle_transfer_between_games, {})
      end

      it 'caps the moved amount at the current balance' do
        create(:game_action, account: account, agent_game: source_ag, contact: contact,
                             action_type: 'load', status: 'success', amount: 20.0)
        ReplyPreference.for_account(account.id).update!(transfer_deposit_shortfall_mode: 'transfer_available')

        expect(source_executor).to receive(:cashout_player)
          .with(hash_including(amount: 8.0)).and_return({ ok: true })
        allow(target_executor).to receive(:load_player).and_return({ ok: true })

        orchestrator.send(:handle_transfer_between_games, {})
      end

      it 'refuses and escalates in shortfall refuse mode' do
        create(:game_action, account: account, agent_game: source_ag, contact: contact,
                             action_type: 'load', status: 'success', amount: 20.0)
        ReplyPreference.for_account(account.id).update!(transfer_deposit_shortfall_mode: 'refuse')
        allow(source_executor).to receive(:cashout_player)

        result = orchestrator.send(:handle_transfer_between_games, {})

        expect(result[:labels]).to include('transfer-deposit-shortfall')
        expect(source_executor).not_to have_received(:cashout_player)
        expect(Games::TelegramNotifier).to have_received(:human_escalation)
          .with(hash_including(reason: a_string_matching(/SHORTFALL/)))
      end

      it 'escalates when no original deposit exists' do
        result = orchestrator.send(:handle_transfer_between_games, {})

        expect(result[:labels]).to include('cashier-action-needed')
      end
    end

    context 'whole mode (balance below cashout_min)' do
      it 'moves the whole balance' do
        ReplyPreference.for_account(account.id).update!(transfer_mode: 'whole')
        allow(source_executor).to receive(:check_player_balance).and_return(7.5)
        stub_transfer_plan(source_slug: 'game_vault', loads: [{ game_slug: 'juwa', amount: 7.5 }])

        expect(source_executor).to receive(:cashout_player)
          .with(hash_including(amount: 7.5)).and_return({ ok: true })
        allow(target_executor).to receive(:load_player).and_return({ ok: true })

        orchestrator.send(:handle_transfer_between_games, {})
      end
    end

    context 'dedup guard (idempotency)' do
      it 'skips the transfer when an identical recent cashout exists' do
        allow(source_executor).to receive(:check_player_balance).and_return(100.0)
        stub_transfer_plan(source_slug: 'game_vault', loads: [{ game_slug: 'juwa', amount: 40.0 }])
        create(:game_action, account: account, agent_game: source_ag, contact: contact,
                             action_type: 'cashout', status: 'pending', amount: 40.0)
        allow(source_executor).to receive(:cashout_player)

        result = orchestrator.send(:handle_transfer_between_games, {})

        expect(result[:labels]).to include('transfer-duplicate-skipped')
        expect(source_executor).not_to have_received(:cashout_player)
      end
    end

    context 'failover wiring (record_api_result)' do
      it 'records an API failure on the source panel when the cashout fails' do
        allow(source_executor).to receive(:check_player_balance).and_return(100.0)
        stub_transfer_plan(source_slug: 'game_vault', loads: [{ game_slug: 'juwa', amount: 40.0 }])
        allow(source_executor).to receive(:cashout_player)
          .and_return({ ok: false, error: 'down', code: 5 })

        expect { orchestrator.send(:handle_transfer_between_games, {}) }
          .to change { source_ag.reload.failure_count }.by(1)
      end

      it 'resets the failure counter on success' do
        source_ag.update!(failure_count: 2)
        allow(source_executor).to receive(:check_player_balance).and_return(100.0)
        stub_transfer_plan(source_slug: 'game_vault', loads: [{ game_slug: 'juwa', amount: 40.0 }])
        allow(source_executor).to receive(:cashout_player).and_return({ ok: true })
        allow(target_executor).to receive(:load_player).and_return({ ok: true })

        orchestrator.send(:handle_transfer_between_games, {})

        expect(source_ag.reload.failure_count).to eq(0)
      end
    end
  end

  describe '#handle_redeem_partial_replay' do
    before do
      allow(orchestrator).to receive(:chosen_game_slug).and_return('game_vault')
    end

    it 'cashes out the amount after the cashout verb, not the first number' do
      stub_customer_text('keep 30 in and cash out 50')

      expect(source_executor).to receive(:cashout_player)
        .with(hash_including(amount: 50.0)).and_return({ ok: true })

      result = orchestrator.send(:handle_redeem_partial_replay, {})
      expect(result[:labels]).to include('partial-cashout')
    end

    it 'skips a duplicate identical cashout inside the dedup window' do
      stub_customer_text('cash out 50')
      create(:game_action, account: account, agent_game: source_ag, contact: contact,
                           action_type: 'cashout', status: 'success', amount: 50.0)
      allow(source_executor).to receive(:cashout_player)

      result = orchestrator.send(:handle_redeem_partial_replay, {})

      expect(result[:labels]).to include('duplicate-skipped')
      expect(source_executor).not_to have_received(:cashout_player)
    end

    it 'asks for an amount when none is parseable' do
      stub_customer_text('cash out some of it')

      result = orchestrator.send(:handle_redeem_partial_replay, {})

      expect(result[:labels]).to include('partial-needs-amount')
    end

    it 'escalates on cashout failure' do
      stub_customer_text('cash out 50')
      allow(source_executor).to receive(:cashout_player)
        .and_return({ ok: false, error: 'down', code: 5 })

      result = orchestrator.send(:handle_redeem_partial_replay, {})

      expect(result[:labels]).to include('needs-human')
      expect(Games::TelegramNotifier).to have_received(:human_escalation)
        .with(hash_including(reason: a_string_matching(/FAILED/)))
    end
  end

  describe '#handle_new_account_reissue' do
    before do
      allow(orchestrator).to receive(:chosen_game_slug).and_return('game_vault')
      contact.update!(custom_attributes: {
                        'game_username_game_vault' => 'old_user',
                        'game_password_game_vault' => 'old_pass'
                      })
    end

    it 'clears stale credentials and stores the freshly minted ones' do
      allow(orchestrator).to receive(:attempt_auto_add_player)
        .and_return([{ ok: true, password: 'newpass1' }, 'new_user', 'newpass1'])

      result = orchestrator.send(:handle_new_account_reissue, {})

      expect(result[:labels]).to include('account-reissued')
      attrs = contact.reload.custom_attributes
      expect(attrs['game_username_game_vault']).to eq('new_user')
      expect(attrs['game_password_game_vault']).to eq('newpass1')
    end

    it 'does not store credentials and escalates when creation fails' do
      allow(orchestrator).to receive(:attempt_auto_add_player)
        .and_return([{ ok: false, error: 'panel down', code: 5 }, 'new_user', 'x'])

      result = orchestrator.send(:handle_new_account_reissue, {})

      expect(result[:labels]).to include('account-creation-failed')
      attrs = contact.reload.custom_attributes
      expect(attrs['game_username_game_vault']).to be_nil
      expect(Games::TelegramNotifier).to have_received(:human_escalation)
    end
  end

  describe '#handle_replay_from_balance (read-only)' do
    before do
      allow(orchestrator).to receive(:chosen_game_slug).and_return('game_vault')
      stub_customer_text('let it ride')
    end

    it 'reports the balance and moves no money' do
      allow(source_executor).to receive(:check_player_balance).and_return(42.0)

      result = orchestrator.send(:handle_replay_from_balance, {})

      expect(result[:reply]).to include('$42')
      # cashout_player/load_player are unstubbed on the verifying double —
      # any money movement here would raise, failing this example.
    end

    it 'escalates when the balance read fails' do
      allow(source_executor).to receive(:check_player_balance).and_raise(StandardError, 'timeout')

      result = orchestrator.send(:handle_replay_from_balance, {})

      expect(result[:labels]).to include('cashier-action-needed')
      expect(Games::TelegramNotifier).to have_received(:human_escalation)
    end

    it 'suggests loading when the balance is zero' do
      allow(source_executor).to receive(:check_player_balance).and_return(0)

      result = orchestrator.send(:handle_replay_from_balance, {})

      expect(result[:reply]).to match(/empty/)
    end
  end

  describe 'fraud guards' do
    describe '#cashout_velocity_state' do
      it 'flags when successful cashouts within the window reach the threshold' do
        create_list(:game_action, 3, account: account, agent_game: source_ag, contact: contact,
                                     action_type: 'cashout', status: 'success', amount: 10.0)

        state = orchestrator.send(:cashout_velocity_state)

        expect(state[:exceeded]).to be true
        expect(state[:count]).to eq(3)
      end

      it 'ignores cashouts outside the window and failed ones' do
        create(:game_action, account: account, agent_game: source_ag, contact: contact,
                             action_type: 'cashout', status: 'success', amount: 10.0,
                             created_at: 30.hours.ago)
        create(:game_action, account: account, agent_game: source_ag, contact: contact,
                             action_type: 'cashout', status: 'failed', amount: 10.0)

        state = orchestrator.send(:cashout_velocity_state)

        expect(state[:exceeded]).to be false
        expect(state[:count]).to eq(0)
      end

      it 'fails closed to a safe default on query errors' do
        allow(GameAction).to receive(:where).and_raise(StandardError, 'db down')

        state = orchestrator.send(:cashout_velocity_state)

        expect(state[:exceeded]).to be false
      end
    end

    describe '#duplicate_recent_load?' do
      it 'detects an identical successful load within 10 minutes' do
        create(:game_action, account: account, agent_game: source_ag, contact: contact,
                             action_type: 'load', status: 'success', amount: 25.0)

        expect(orchestrator.send(:duplicate_recent_load?, 25.0)).to be true
        expect(orchestrator.send(:duplicate_recent_load?, 26.0)).to be false
      end

      it 'returns false for non-positive amounts' do
        expect(orchestrator.send(:duplicate_recent_load?, 0)).to be false
      end
    end

    describe '#recent_cashout_duplicate?' do
      it 'fails OPEN (returns false) on query errors so legit payouts are not blocked' do
        allow(GameAction).to receive(:where).and_raise(StandardError, 'db down')

        expect(orchestrator.send(:recent_cashout_duplicate?, agent_game: source_ag, amount: 10)).to be false
      end
    end
  end

  describe 'AgentGame failover (record_api_failure!/success!)' do
    it 'degrades an active panel after 3 consecutive failures and alerts Telegram once' do
      source_ag.update!(failure_count: 2, status: 'active')

      source_ag.record_api_failure!

      expect(source_ag.reload.status).to eq('degraded')
      expect(Games::TelegramNotifier).to have_received(:human_escalation)
        .with(hash_including(reason: a_string_matching(/GAME DOWN/))).once
    end

    it 'resets the counter on success but leaves a degraded panel degraded' do
      source_ag.update!(failure_count: 3, status: 'degraded')

      source_ag.record_api_success!

      expect(source_ag.reload.failure_count).to eq(0)
      expect(source_ag.status).to eq('degraded')
    end
  end
end
