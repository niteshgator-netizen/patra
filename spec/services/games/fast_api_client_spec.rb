# frozen_string_literal: true

# FastAPI panel family (Vblink + Ultra Panda are sibling skins of the same
# provider client). All HTTP mocked via WebMock — no panel is ever touched.
require 'rails_helper'

RSpec.describe Games::FastApi::Client do
  let(:account) { create(:account) }
  let(:base_url) { 'https://fastapi.test' }

  shared_examples 'a fastapi sibling' do |client_class, slug|
    let(:game) { create(:game, slug: slug, api_base_url: base_url) }
    let(:agent_game) do
      create(:agent_game, account: account, game: game,
                          credentials: { 'app_id' => 'app1', 'app_secret' => 'sekret',
                                         'agent_account' => 'agent', 'agent_password' => 'pw' })
    end
    let(:client) { client_class.new(agent_game) }

    def stub_fastapi(path, code:, msg: nil, data: nil)
      stub_request(:post, "#{base_url}#{path}")
        .to_return(status: 200,
                   body: { 'code' => code, 'msg' => msg, 'data' => data }.to_json,
                   headers: { 'Content-Type' => 'application/json' })
    end

    it 'maps code 7 (account format error — underscores rejected) to a typed error' do
      stub_fastapi('/fast/user/create', code: 7)

      expect { client.add_user(account: 'bad_name', password: 'pass1234') }
        .to raise_error(Games::FastApi::Client::FastApiError) { |e|
          expect(e.code).to eq(7)
          expect(e.message).to eq('Account format error')
        }
    end

    it 'maps code 3 (parameter error — e.g. decimal amounts rejected) to a typed error' do
      stub_fastapi('/fast/user/deposit', code: 3)

      expect { client.recharge(user_id: 'player1', amount: '25.55', order_id: 'ord1') }
        .to raise_error(Games::FastApi::Client::FastApiError) { |e|
          expect(e.code).to eq(3)
          expect(e.message).to eq('Parameter Error')
        }
    end

    it 'strips non-alphanumerics from requestid (panel rejects underscores)' do
      stub = stub_request(:post, "#{base_url}/fast/user/deposit")
             .with(body: hash_including('requestid' => 'patabc123'))
             .to_return(status: 200, body: { 'code' => 200, 'msg' => 'Success', 'data' => {} }.to_json,
                        headers: { 'Content-Type' => 'application/json' })

      client.recharge(user_id: 'player1', amount: '25', order_id: 'pat_abc_123')

      expect(stub).to have_been_requested
    end

    it 'signs every request (md5 of sorted params + app secret)' do
      stub = stub_request(:post, "#{base_url}/fast/user/balance")
             .with { |req| req.body.include?('sign=') }
             .to_return(status: 200, body: { 'code' => 200, 'data' => { 'balance' => '5' } }.to_json,
                        headers: { 'Content-Type' => 'application/json' })

      client.user_balance(user_id: 'player1')

      expect(stub).to have_been_requested
    end

    it 'resolves user ids locally — the account name IS the id (no HTTP)' do
      expect(client.get_user_id(account_name: 'player1'))
        .to eq({ 'code' => 200, 'msg' => 'Success', 'data' => { 'user_id' => 'player1' } })
      expect(WebMock).not_to have_requested(:post, %r{#{base_url}})
    end

    it 'normalizes balance to user_balance for the executor contract' do
      stub_fastapi('/fast/user/balance', code: 200, data: { 'balance' => '12.5' })

      body = client.user_balance(user_id: 'player1')

      expect(body.dig('data', 'user_balance')).to eq('12.5')
    end

    it 'raises a verification error when create says OK but the user does not exist (silent fail net)' do
      stub_fastapi('/fast/user/create', code: 200)
      stub_fastapi('/fast/user/balance', code: 2) # User Does Not Exist

      expect { client.add_user(account: 'ghost1', password: 'pass1234') }
        .to raise_error(Games::FastApi::Client::FastApiError, /not found after creation/)
    end

    it 'documents code 12 (User Already Exist) for shared-namespace reuse — and NOT 20' do
      expect(client.already_exists_code?(12)).to be true
      expect(client.already_exists_code?(20)).to be false # 20 = Password error on FastAPI
    end

    it 'raises a typed timeout error (never nil, never silent)' do
      stub_request(:post, "#{base_url}/fast/user/deposit").to_timeout

      expect { client.recharge(user_id: 'player1', amount: '25', order_id: 'ord1') }
        .to raise_error(Games::FastApi::Client::FastApiError, /timeout/i)
    end

    it 'raises a typed error on invalid JSON from the panel' do
      stub_request(:post, "#{base_url}/fast/user/balance")
        .to_return(status: 200, body: '<html>cloudflare says no</html>')

      expect { client.user_balance(user_id: 'player1') }
        .to raise_error(Games::FastApi::Client::FastApiError) { |e| expect(e.code).to eq(-2) }
    end

    it 'raises a typed error on an HTTP-level failure' do
      stub_request(:post, "#{base_url}/fast/user/balance").to_return(status: 502, body: 'bad gateway')

      expect { client.user_balance(user_id: 'player1') }
        .to raise_error(Games::FastApi::Client::FastApiError) { |e| expect(e.code).to eq(502) }
    end

    it 'requires app credentials at construction' do
      agent_game.update!(credentials: {})
      with_modified_env "#{slug.upcase}_APP_ID": '', "#{slug.upcase}_APP_SECRET": '' do
        expect { client_class.new(agent_game.reload) }.to raise_error(ArgumentError, /app_id/)
      end
    end
  end

  describe Games::Vblink::Client do
    it_behaves_like 'a fastapi sibling', Games::Vblink::Client, 'vblink'
  end

  describe Games::UltraPanda::Client do
    it_behaves_like 'a fastapi sibling', Games::UltraPanda::Client, 'ultra_panda'
  end

  describe 'GameVault family shared player namespace (game_vault + vegas_sweeps)' do
    let(:gv_game) { create(:game, slug: 'game_vault', api_base_url: base_url) }
    let(:vs_game) { create(:game, slug: 'vegas_sweeps', api_base_url: base_url) }
    let(:gv) { Games::GameVault::Client.new(create(:agent_game, account: account, game: gv_game)) }
    let(:vs) { Games::GameVault::Client.new(create(:agent_game, account: account, game: vs_game)) }

    it 'documents code 20 as already-exists on both skins (sibling-created accounts get reused)' do
      expect(gv.already_exists_code?(20)).to be true
      expect(Games::VegasSweeps::Client.superclass).to eq(Games::GameVault::Client)
      expect(vs.already_exists_code?(20)).to be true
    end
  end
end
