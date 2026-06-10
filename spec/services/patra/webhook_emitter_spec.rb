# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Patra::WebhookEmitter do
  let(:account) { create(:account) }
  let(:url) { 'https://example.com/patra-hook' }

  describe '.emit' do
    it 'is a zero-cost no-op without a webhook_url' do
      expect(Patra::WebhookEmitJob).not_to receive(:perform_later)
      expect(described_class.emit(account: account, event: 'load.success', payload: { amount: 5 })).to be(false)
    end

    it 'enqueues delivery with plain-JSON payload when a URL is configured' do
      account.update!(custom_attributes: { 'webhook_url' => url })
      expect(Patra::WebhookEmitJob).to receive(:perform_later)
        .with(account.id, 'load.success', { 'amount' => 5.0 })

      expect(described_class.emit(account: account, event: 'load.success', payload: { amount: 5.0 })).to be(true)
    end

    it 'swallows enqueue failures' do
      account.update!(custom_attributes: { 'webhook_url' => url })
      allow(Patra::WebhookEmitJob).to receive(:perform_later).and_raise(StandardError, 'redis down')

      expect { described_class.emit(account: account, event: 'load.success') }.not_to raise_error
    end
  end

  describe '.deliver' do
    before { account.update!(custom_attributes: { 'webhook_url' => url }) }

    it 'POSTs the event envelope' do
      stub = stub_request(:post, url).to_return(status: 200)

      result = described_class.deliver(account: account, event: 'payment.confirmed', payload: { 'amount' => 50 })

      expect(result[:ok]).to be(true)
      expect(stub.with do |req|
        body = JSON.parse(req.body)
        body['event'] == 'payment.confirmed' &&
          body['account_id'] == account.id &&
          body['payload'] == { 'amount' => 50 }
      end).to have_been_requested
    end

    it 'retries once and swallows network errors' do
      stub_request(:post, url).to_raise(Errno::ECONNREFUSED)

      result = nil
      expect { result = described_class.deliver(account: account, event: 'load.failed') }.not_to raise_error
      expect(result[:ok]).to be(false)
      expect(result[:attempts]).to eq(2)
    end

    it 'signs the body when webhook_secret is set' do
      account.update!(custom_attributes: { 'webhook_url' => url, 'webhook_secret' => 's3cret' })
      captured = nil
      stub_request(:post, url).with { |req| captured = req }.to_return(status: 200)

      described_class.deliver(account: account, event: 'cashout.executed')

      expected = OpenSSL::HMAC.hexdigest('SHA256', 's3cret', captured.body)
      expect(captured.headers['X-Patra-Signature']).to eq(expected)
    end

    it 'no-ops without a URL' do
      account.update!(custom_attributes: {})
      expect(described_class.deliver(account: account, event: 'load.success')).to include(ok: false, reason: 'no_url')
    end
  end
end
