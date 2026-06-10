# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Games::AspNetPanel::BaseClient do
  let(:account) { create(:account) }
  let(:game) { create(:game, slug: 'panda_master', name: 'Panda Master') }
  let(:agent_game) do
    create(:agent_game, account: account, game: game,
                        credentials: { 'agent_username' => 'agent1', 'agent_password' => 'pw',
                                       'asp_session_id' => 'sid123' })
  end
  let(:client) { Games::PandaMaster::Client.new(agent_game) }
  let(:list_url) { 'https://pandamaster.vip/Module/AccountManager/AccountsList.aspx' }
  let(:www_list_url) { 'https://www.pandamaster.vip/Module/AccountManager/AccountsList.aspx' }
  let(:big_page) { "<html>#{'x' * 9000}__VIEWSTATE updateBalance(\"Balance:123.45\")</html>" }

  it 'follows a same-host redirect once and extracts the balance' do
    stub_request(:get, list_url).to_return(status: 301, headers: { 'Location' => www_list_url })
    stub_request(:get, www_list_url).to_return(status: 200, body: big_page)

    result = client.agent_balance

    expect(result.dig('data', 'agent_balance')).to eq(123.45)
  end

  it 'raises a loud ClientError (not a silent nil) on an unresolved redirect' do
    stub_request(:get, list_url)
      .to_return(status: 301, headers: { 'Location' => 'https://elsewhere.example.com/x.aspx' })
    allow(Games::AspNetPanel::SessionRefresher).to receive(:new)
      .and_return(instance_double(Games::AspNetPanel::SessionRefresher, refresh!: { ok: false, error: 'nope' }))

    expect { client.agent_balance }.to raise_error(Games::ClientError, /redirect/)
  end

  it 'does not follow redirects to the login page' do
    stub_request(:get, list_url)
      .to_return(status: 301, headers: { 'Location' => 'https://pandamaster.vip/default.aspx' })
    stub_request(:get, 'https://pandamaster.vip/default.aspx')
    allow(Games::AspNetPanel::SessionRefresher).to receive(:new)
      .and_return(instance_double(Games::AspNetPanel::SessionRefresher, refresh!: { ok: false, error: 'nope' }))

    expect { client.agent_balance }.to raise_error(Games::ClientError)
    expect(a_request(:get, 'https://pandamaster.vip/default.aspx')).not_to have_been_made
  end
end
