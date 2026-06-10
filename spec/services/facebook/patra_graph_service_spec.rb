# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Facebook::PatraGraphService do
  let(:token_url) { %r{graph\.facebook\.com/v18\.0/oauth/access_token} }

  def stub_graph_error(code:, message:)
    stub_request(:get, token_url).to_return(
      status: 400,
      body: { error: { message: message, code: code, type: 'OAuthException' } }.to_json,
      headers: { 'Content-Type' => 'application/json' }
    )
  end

  it 'raises a typed error carrying the FB code on a dead token (190)' do
    stub_graph_error(code: 190, message: 'Error validating access token')

    expect do
      described_class.exchange_user_token('dead', app_id: 'id', app_secret: 'sec')
    end.to raise_error(described_class::GraphApiError) { |e|
      expect(e.fb_code).to eq(190)
      expect(e).to be_token_expired
      expect(e).not_to be_rate_limited
    }
  end

  it 'flags rate-limit codes as retryable' do
    stub_graph_error(code: 4, message: 'Application request limit reached')

    expect do
      described_class.exchange_user_token('tok', app_id: 'id', app_secret: 'sec')
    end.to raise_error(described_class::GraphApiError) { |e|
      expect(e).to be_rate_limited
      expect(e).not_to be_token_expired
    }
  end

  it 'remains rescuable as StandardError (no caller breakage)' do
    stub_graph_error(code: 1, message: 'Unknown')

    expect do
      described_class.exchange_user_token('tok', app_id: 'id', app_secret: 'sec')
    end.to raise_error(StandardError, /Facebook Graph error/)
  end

  it 'returns the token on success' do
    stub_request(:get, token_url).to_return(
      status: 200,
      body: { access_token: 'long_lived' }.to_json,
      headers: { 'Content-Type' => 'application/json' }
    )

    expect(described_class.exchange_user_token('tok', app_id: 'id', app_secret: 'sec')).to eq('long_lived')
  end
end
