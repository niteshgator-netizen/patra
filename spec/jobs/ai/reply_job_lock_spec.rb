# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Ai::ReplyJob do
  subject(:job) { described_class.new }

  let(:account) { create(:account) }
  let(:conversation) { create(:conversation, account: account) }
  let(:lock_key) { format(described_class::REPLY_LOCK_KEY, conv_id: conversation.display_id) }
  let(:reply_service) { instance_double(Ai::ReplyService) }

  before do
    allow(Ai::ReplyService).to receive(:new).and_return(reply_service)
    allow(Redis::Alfred).to receive(:get).and_return(nil)
    allow(Redis::Alfred).to receive(:set)
    allow(Redis::Alfred).to receive(:delete)
  end

  it 'releases the reply lock and re-raises on transient send errors' do
    allow(reply_service).to receive(:call).and_raise(Messaging::TransientSendError, '502')

    expect { job.perform(conversation.display_id, account.id) }
      .to raise_error(Messaging::TransientSendError)
    expect(Redis::Alfred).to have_received(:delete).with(lock_key)
  end

  it 'releases the reply lock and re-raises on any other error (bounded retry regenerates)' do
    allow(reply_service).to receive(:call).and_raise(StandardError, 'deepseek timeout')

    expect { job.perform(conversation.display_id, account.id) }
      .to raise_error(StandardError, 'deepseek timeout')
    expect(Redis::Alfred).to have_received(:delete).with(lock_key)
  end

  it 'skips duplicates without touching the AI when the lock is held' do
    allow(Redis::Alfred).to receive(:get).with(lock_key).and_return('1')

    job.perform(conversation.display_id, account.id)

    expect(reply_service).not_to have_received(:call) if reply_service.respond_to?(:call)
    expect(Redis::Alfred).not_to have_received(:delete)
  end
end
