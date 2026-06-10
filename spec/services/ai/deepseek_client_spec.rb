# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Ai::DeepseekClient do
  let(:endpoint) { described_class::ENDPOINT }

  def body_with(content: nil, reasoning: nil)
    {
      choices: [{ message: { content: content, reasoning_content: reasoning } }]
    }.to_json
  end

  around do |example|
    with_modified_env DEEPSEEK_API_KEY: 'test-key' do
      example.run
    end
  end

  describe '.complete' do
    it 'returns content when present' do
      stub_request(:post, endpoint)
        .to_return(status: 200, body: body_with(content: 'hello'), headers: { 'Content-Type' => 'application/json' })

      expect(described_class.complete(system_prompt: 'sys', user_content: 'hi')).to eq('hello')
    end

    it 'falls back to reasoning_content when content is blank (reasoning models)' do
      stub_request(:post, endpoint)
        .to_return(status: 200, body: body_with(content: '', reasoning: 'from reasoning'),
                   headers: { 'Content-Type' => 'application/json' })

      expect(described_class.complete(system_prompt: 'sys', user_content: 'hi')).to eq('from reasoning')
    end

    it 'returns nil when both content and reasoning_content are blank' do
      stub_request(:post, endpoint)
        .to_return(status: 200, body: body_with(content: '', reasoning: ''),
                   headers: { 'Content-Type' => 'application/json' })

      expect(described_class.complete(system_prompt: 'sys', user_content: 'hi')).to be_nil
    end

    it 'returns nil without making a request when the API key is missing' do
      with_modified_env DEEPSEEK_API_KEY: nil do
        expect(described_class.complete(system_prompt: 'sys', user_content: 'hi')).to be_nil
        expect(WebMock).not_to have_requested(:post, endpoint)
      end
    end

    it 'retries once on a 5xx and succeeds' do
      stub_request(:post, endpoint)
        .to_return({ status: 500, body: 'oops' },
                   { status: 200, body: body_with(content: 'recovered'),
                     headers: { 'Content-Type' => 'application/json' } })

      expect(described_class.complete(system_prompt: 'sys', user_content: 'hi')).to eq('recovered')
      expect(WebMock).to have_requested(:post, endpoint).twice
    end

    it 'returns nil after two consecutive 5xx responses' do
      stub_request(:post, endpoint).to_return(status: 503, body: 'down')

      expect(described_class.complete(system_prompt: 'sys', user_content: 'hi')).to be_nil
      expect(WebMock).to have_requested(:post, endpoint).twice
    end

    it 'does NOT retry on 4xx' do
      stub_request(:post, endpoint).to_return(status: 401, body: 'bad key')

      expect(described_class.complete(system_prompt: 'sys', user_content: 'hi')).to be_nil
      expect(WebMock).to have_requested(:post, endpoint).once
    end

    it 'retries once on a network timeout and succeeds' do
      stub_request(:post, endpoint)
        .to_timeout.then
        .to_return(status: 200, body: body_with(content: 'after timeout'),
                   headers: { 'Content-Type' => 'application/json' })

      expect(described_class.complete(system_prompt: 'sys', user_content: 'hi')).to eq('after timeout')
    end

    it 'returns nil (never raises) when every attempt times out' do
      stub_request(:post, endpoint).to_timeout

      expect { described_class.complete(system_prompt: 'sys', user_content: 'hi') }.not_to raise_error
      expect(described_class.complete(system_prompt: 'sys', user_content: 'hi')).to be_nil
    end

    it 'sends the system prompt and user turn in order' do
      stub_request(:post, endpoint)
        .with(body: hash_including(
          'messages' => [
            { 'role' => 'system', 'content' => 'sys' },
            { 'role' => 'user', 'content' => 'hi' }
          ]
        ))
        .to_return(status: 200, body: body_with(content: 'ok'), headers: { 'Content-Type' => 'application/json' })

      expect(described_class.complete(system_prompt: 'sys', user_content: 'hi')).to eq('ok')
    end
  end
end
