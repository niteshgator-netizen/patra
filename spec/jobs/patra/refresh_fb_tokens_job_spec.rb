# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Patra::RefreshFbTokensJob do
  subject(:job) { described_class.new }

  let(:account) { create(:account) }
  let(:inbox) do
    create(:inbox, account: account,
                   channel: create(:channel_api, account: account,
                                                 additional_attributes: {
                                                   'fb_page_id' => 'pg1',
                                                   'fb_user_long_lived_token' => 'ut',
                                                   'fb_page_token_obtained_at' => 55.days.ago.iso8601
                                                 }))
  end

  before do
    allow(job).to receive(:fb_api_inboxes).and_return(Inbox.where(id: inbox.id))
    allow(job).to receive(:update_identity_statuses)
    allow(Games::TelegramNotifier).to receive(:api_error).and_return({ ok: true })

    stamps = {}
    allow(Redis::Alfred).to receive(:get) { |key| stamps[key] }
    allow(Redis::Alfred).to receive(:set) { |key, value, **| stamps[key] = value }
  end

  it 'alerts once per token per day when refresh fails' do
    allow(Facebook::PatraGraphService).to receive(:refresh_page_access_token).and_return(nil)

    job.perform
    job.perform

    expect(Games::TelegramNotifier).to have_received(:api_error).once
      .with(hash_including(account: account, details: include('pg1')))
  end

  it 'alerts when a token is expiring with no refresh path' do
    inbox.channel.update!(additional_attributes: {
                            'fb_page_id' => 'pg1',
                            'fb_page_token_obtained_at' => 55.days.ago.iso8601
                          })

    job.perform

    expect(Games::TelegramNotifier).to have_received(:api_error).once
  end

  it 'stays silent on a healthy refresh' do
    allow(Facebook::PatraGraphService).to receive(:refresh_page_access_token).and_return('fresh')

    job.perform

    expect(Games::TelegramNotifier).not_to have_received(:api_error)
    expect(inbox.reload.channel.additional_attributes['fb_page_access_token']).to eq('fresh')
  end
end
