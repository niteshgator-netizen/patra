# frozen_string_literal: true

# Idempotency + safety specs for the payment/ops jobs touched by launch-night
# hardening. Everything external (Telegram, dispatcher, panels) is mocked.
require 'rails_helper'

RSpec.describe 'Patra payment jobs' do
  let(:account) { create(:account) }
  let(:inbox) { create(:inbox, account: account) }
  let(:contact) { create(:contact, account: account) }
  let(:conversation) { create(:conversation, account: account, inbox: inbox, contact: contact) }

  describe Payments::AnnounceVerifiedPaymentJob do
    before do
      allow(Messaging::OutboundDispatcher).to receive(:send)
    end

    it 'announces once and stamps the awaiting-load attributes' do
      described_class.perform_now(account.id, contact.id, conversation.display_id, 25.0)

      expect(Messaging::OutboundDispatcher).to have_received(:send).once
      attrs = conversation.reload.additional_attributes
      expect(attrs['awaiting_load_amount']).to eq(25.0)
      expect(attrs['awaiting_load_set_at']).to be_present
    end

    it 'skips a duplicate enqueue for the same amount inside the ask window (idempotent)' do
      described_class.perform_now(account.id, contact.id, conversation.display_id, 25.0)
      described_class.perform_now(account.id, contact.id, conversation.display_id, 25.0)

      expect(Messaging::OutboundDispatcher).to have_received(:send).once
    end

    it 'still announces a different amount' do
      described_class.perform_now(account.id, contact.id, conversation.display_id, 25.0)
      described_class.perform_now(account.id, contact.id, conversation.display_id, 40.0)

      expect(Messaging::OutboundDispatcher).to have_received(:send).twice
    end

    it 'never raises into the queue (no dead-letter from a missing record)' do
      expect { described_class.perform_now(account.id, 999_999, conversation.display_id, 25.0) }
        .not_to raise_error
      expect(Messaging::OutboundDispatcher).not_to have_received(:send)
    end
  end

  describe Payments::HandleHealthMonitor do
    let!(:handle) do
      PaymentHandle.create!(account: account, platform: 'cashapp', handle: 'kara', priority: 1, status: 'active')
    end

    before do
      allow(Games::TelegramNotifier).to receive(:api_error).and_return({ ok: true })
    end

    def fail_actions(count)
      ag = create(:agent_game, account: account)
      count.times do
        create(:game_action, account: account, agent_game: ag, contact: contact,
                             action_type: 'load', status: 'failed', payment_handle: 'kara', amount: 10)
      end
    end

    it 'disables a failing handle and alerts telegram via the public API' do
      fail_actions(4)

      described_class.check_all(account)

      expect(handle.reload.status).to eq('disabled')
      expect(Games::TelegramNotifier).to have_received(:api_error)
        .with(hash_including(account: account, message: a_string_matching(/flagged/)))
    end

    it 'does not re-alert an already-disabled handle on the next sweep (idempotent)' do
      fail_actions(4)

      described_class.check_all(account)
      described_class.check_all(account)

      expect(Games::TelegramNotifier).to have_received(:api_error).once
    end

    it 'leaves healthy handles alone' do
      ag = create(:agent_game, account: account)
      create(:game_action, account: account, agent_game: ag, contact: contact,
                           action_type: 'load', status: 'success', payment_handle: 'kara', amount: 10)

      described_class.check_all(account)

      expect(handle.reload.status).to eq('active')
    end

    it 'survives a telegram failure without crashing the sweep' do
      fail_actions(4)
      allow(Games::TelegramNotifier).to receive(:api_error).and_raise(StandardError, 'tg down')

      expect { described_class.check_all(account) }.not_to raise_error
      expect(handle.reload.status).to eq('disabled')
    end
  end

  describe Webhooks::TelegramEventsJob, 'update dedup' do
    let(:params) do
      { bot_token: 'tok123', telegram: { update_id: 42, message: { text: 'hi' } } }.with_indifferent_access
    end

    before do
      allow(Channel::Telegram).to receive(:find_by).and_return(nil) # discard path after dedup
    end

    it 'processes the first delivery and skips an identical retry' do
      redis_seen = {}
      allow(Sidekiq).to receive(:redis) do |&block|
        conn = double('redis')
        allow(conn).to receive(:set) do |key, _v, opts|
          next false if redis_seen[key]

          redis_seen[key] = true if opts[:nx]
          true
        end
        block.call(conn)
      end

      expect(Channel::Telegram).to receive(:find_by).once

      described_class.perform_now(params)
      described_class.perform_now(params) # retry — deduped before channel lookup
    end

    it 'fails open when redis is down' do
      allow(Sidekiq).to receive(:redis).and_raise(StandardError, 'redis down')

      expect(Channel::Telegram).to receive(:find_by).once
      described_class.perform_now(params)
    end
  end
end
