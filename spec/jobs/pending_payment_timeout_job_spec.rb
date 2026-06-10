# frozen_string_literal: true

require 'rails_helper'

RSpec.describe PendingPaymentTimeoutJob do
  subject(:job) { described_class.new }

  let(:account) { create(:account) }
  let(:agent_game) { create(:agent_game, account: account) }
  let(:redis_store) { {} }
  let(:fake_redis) do
    store = redis_store
    double('redis').tap do |r|
      allow(r).to receive(:get) { |key| store[key] }
      allow(r).to receive(:setex) { |key, _ttl, value| store[key] = value }
    end
  end

  before do
    allow(Redis).to receive(:new).and_return(fake_redis)
    allow(Games::TelegramNotifier).to receive(:api_error).and_return({ ok: true })
  end

  it 'alerts once (idempotent) for actions stuck pending >1h and never mutates them' do
    action = create(:game_action, account: account, agent_game: agent_game,
                                  action_type: 'load', status: 'pending', amount: 50,
                                  created_at: 2.hours.ago)

    job.perform
    job.perform

    expect(Games::TelegramNotifier).to have_received(:api_error).once
      .with(hash_including(message: include('PENDING'), details: include("##{action.id}")))
    expect(action.reload.status).to eq('pending')
  end

  it 'does not alert when nothing is stuck' do
    create(:game_action, account: account, agent_game: agent_game,
                         action_type: 'load', status: 'pending', amount: 50,
                         created_at: 10.minutes.ago)

    job.perform

    expect(Games::TelegramNotifier).not_to have_received(:api_error)
    expect(redis_store).to be_empty
  end
end
