# frozen_string_literal: true

# ASP.NET panel base client (Cluster 1: milky_way, fire_kirin, panda_master,
# orion_stars). All HTTP mocked via WebMock; CapSolver/session refresher mocked.
require 'rails_helper'

RSpec.describe Games::AspNetPanel::BaseClient do
  let(:account) { create(:account) }
  let(:base_url) { Games::MilkyWay::Client::BASE_URL }
  let(:search_url) { "#{base_url}/Module/AccountManager/AccountsList.aspx" }
  let(:game) { create(:game, slug: 'milky_way', name: 'Milky Way') }
  let(:agent_game) do
    create(:agent_game, account: account, game: game,
                        credentials: { 'agent_username' => 'agent007', 'asp_session_id' => 'sid123' })
  end
  let(:client) { Games::MilkyWay::Client.new(agent_game) }

  # A "real" authenticated panel page: long body + viewstate tokens.
  def panel_page(extra = '')
    <<~HTML + ('x' * 9000)
      <input id="__VIEWSTATE" value="VSTATE" />
      <input id="__VIEWSTATEGENERATOR" value="VSGEN" />
      <input id="__EVENTVALIDATION" value="EVAL" />
      #{extra}
    HTML
  end

  def login_redirect_page
    "<script>window.location='/default.aspx';</script>"
  end

  before do
    allow_any_instance_of(described_class).to receive(:sleep_jitter) # no real waits
  end

  describe 'construction' do
    it 'requires agent_username in credentials' do
      agent_game.update!(credentials: { 'asp_session_id' => 'sid123' })

      expect { Games::MilkyWay::Client.new(agent_game.reload) }
        .to raise_error(ArgumentError, /agent_username/)
    end
  end

  describe '#get_user_id' do
    it 'resolves a username to uid:gid via the search dance' do
      stub_request(:get, search_url).to_return(status: 200, body: panel_page)
      stub_request(:post, search_url)
        .with(body: /txtSearch=player1/)
        .to_return(status: 200, body: panel_page("updateSelect('12,34')"))

      result = client.get_user_id(account_name: 'player1')

      expect(result.dig('data', 'user_id')).to eq('12:34')
    end

    it 'returns a structured not-found (no raise, no nil)' do
      stub_request(:get, search_url).to_return(status: 200, body: panel_page)
      stub_request(:post, search_url).to_return(status: 200, body: panel_page)

      result = client.get_user_id(account_name: 'ghost')

      expect(result['code']).to eq(-1)
      expect(result['data']).to be_nil
      expect(result['msg']).to match(/not found/)
    end
  end

  describe '#recharge (tourl=0 dance)' do
    def stub_dance(final_body:)
      stub_request(:get, %r{#{base_url}/Tools/Operating\.ashx}).to_return(status: 200, body: '{"valid":true}')
      stub_request(:post, search_url)
        .with(body: /tourl=0/)
        .to_return(status: 200, body: 'Module/AccountManager/Recharge.aspx?x=1|extra')
      stub_request(:get, "#{base_url}/Module/AccountManager/Recharge.aspx?x=1")
        .to_return(status: 200, body: panel_page)
      stub_request(:post, "#{base_url}/Module/AccountManager/Recharge.aspx?x=1")
        .to_return(status: 200, body: final_body)
    end

    it 'succeeds when the panel confirms' do
      stub_dance(final_body: panel_page('Confirmed successful'))

      result = client.recharge(user_id: '12:34', amount: 25, order_id: 'ord1')

      expect(result['code']).to eq(0)
      expect(result.dig('data', 'amount')).to eq(25)
    end

    it 'rejects decimal amounts before touching the panel form (panel takes whole dollars)' do
      expect { client.recharge(user_id: '12:34', amount: 25.5, order_id: 'ord1') }
        .to raise_error(Games::ClientError, /whole-dollar/)
    end

    it 'maps the panel alert to a structured error on failure' do
      stub_dance(final_body: panel_page('showAlter("Insufficient agent balance")'))

      expect { client.recharge(user_id: '12:34', amount: 25, order_id: 'ord1') }
        .to raise_error(Games::ClientError, /Insufficient agent balance/)
    end

    it 'rejects malformed user_id (must be uid:gid)' do
      expect { client.recharge(user_id: '1234', amount: 25, order_id: 'ord1') }
        .to raise_error(Games::ClientError, /uid:gid/)
    end
  end

  describe 'error surfaces (failures bubble as typed errors, never nils)' do
    it 'maps timeouts to Games::ClientError' do
      stub_request(:get, search_url).to_timeout

      expect { client.agent_balance }.to raise_error(Games::ClientError, /Timeout/)
    end

    it 'maps HTTP 5xx to Games::ClientError with the status code' do
      stub_request(:get, search_url).to_return(status: 500, body: 'boom')

      expect { client.agent_balance }
        .to raise_error(Games::ClientError) { |e| expect(e.code).to eq(500) }
    end
  end

  describe 'reactive session refresh' do
    it 'refreshes a dead session once and retries the original request' do
      refresher = instance_double(Games::AspNetPanel::SessionRefresher)
      allow(Games::AspNetPanel::SessionRefresher).to receive(:new).and_return(refresher)
      allow(refresher).to receive(:refresh!) do
        agent_game.update!(credentials: agent_game.credentials.merge(
          'asp_session_id' => 'fresh_sid', 'agent_password' => 'pw'
        ))
        { ok: true }
      end
      agent_game.update!(credentials: agent_game.credentials.merge('agent_password' => 'pw'))

      stub_request(:get, search_url)
        .with(headers: { 'Cookie' => 'ASP.NET_SessionId=sid123' })
        .to_return(status: 200, body: login_redirect_page) # dead session marker
      stub_request(:get, search_url)
        .with(headers: { 'Cookie' => 'ASP.NET_SessionId=fresh_sid' })
        .to_return(status: 200, body: panel_page('updateBalance("Balance:55.5")'))

      result = client.agent_balance

      expect(result.dig('data', 'agent_balance')).to eq(55.5)
      expect(refresher).to have_received(:refresh!).once
    end

    it 'does not loop on a failed refresh — surfaces a typed error' do
      allow_any_instance_of(described_class).to receive(:refresh_session_locked!).and_return(false)
      stub_request(:get, search_url).to_return(status: 200, body: login_redirect_page)

      # dead login page has no __VIEWSTATE → get_user_id surfaces the scrape error
      expect { client.get_user_id(account_name: 'player1') }
        .to raise_error(Games::ClientError, /__VIEWSTATE/)
      expect(WebMock).to have_requested(:get, search_url).once
    end

    it 'raises a clear error when no session can be established at all' do
      agent_game.update!(credentials: { 'agent_username' => 'agent007' }) # no session id
      allow_any_instance_of(described_class).to receive(:refresh_session_locked!).and_return(false)

      expect { Games::MilkyWay::Client.new(agent_game.reload).agent_balance }
        .to raise_error(Games::ClientError, /Could not establish session/)
    end
  end

  describe 'panel name sanitization' do
    it 'strips invalid chars and caps at 13 chars' do
      expect(client.send(:sanitize_panel_name, 'kara-mw!@#_123456789')).to eq('karamw_123456')
    end
  end
end
