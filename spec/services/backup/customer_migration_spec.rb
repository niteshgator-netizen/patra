# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Backup::CustomerMigration do
  let(:account) { create(:account) }
  let(:from_page) { create(:backup_page, account: account, status: 'banned', page_name: 'Old Page') }
  let(:to_page) { create(:backup_page, account: account, status: 'active', page_name: 'New Page') }

  before do
    allow(Games::TelegramNotifier).to receive(:api_error).and_return({ ok: true })
    allow(described_class).to receive(:sleep) # rate-limit sleeps don't slow the suite
  end

  def contact_with_inbound(at:)
    contact = create(:contact, account: account, last_activity_at: at)
    conversation = create(:conversation, account: account, contact: contact)
    create(:message, account: account, conversation: conversation,
                     message_type: :incoming, sender: contact, created_at: at)
    contact
  end

  it 'notes only contacts with an inbound message inside 24h and always alerts the operator' do
    inside = contact_with_inbound(at: 1.hour.ago)
    outside = contact_with_inbound(at: 30.hours.ago)

    expect do
      described_class.migrate(account, from: from_page, to: to_page)
    end.to change { inside.conversations.last.messages.outgoing.count }.by(1)

    expect(outside.conversations.last.messages.outgoing.count).to eq(0)
    expect(Games::TelegramNotifier).to have_received(:api_error).once
      .with(hash_including(account: account, message: include('Old Page').and(include('New Page'))))
    expect(account.reload.custom_attributes['backup_migration']).to include('notes_sent' => 1)
  end

  it 'respects PATRA_MIGRATION_MAX_NOTES' do
    contacts = Array.new(4) { contact_with_inbound(at: 1.hour.ago) }

    with_modified_env PATRA_MIGRATION_MAX_NOTES: '2' do
      expect(described_class.migrate(account, from: from_page, to: to_page)).to eq(2)
    end

    noted = contacts.count { |c| c.conversations.last.messages.outgoing.count == 1 }
    expect(noted).to eq(2)
  end

  it 'sends no notes when the cap is 0 but still alerts' do
    contact_with_inbound(at: 1.hour.ago)

    with_modified_env PATRA_MIGRATION_MAX_NOTES: '0' do
      expect(described_class.migrate(account, from: from_page, to: to_page)).to eq(0)
    end

    expect(Games::TelegramNotifier).to have_received(:api_error).once
  end

  it 'still sends notes when Telegram is down' do
    allow(Games::TelegramNotifier).to receive(:api_error).and_raise(StandardError, 'telegram down')
    inside = contact_with_inbound(at: 1.hour.ago)

    expect do
      described_class.migrate(account, from: from_page, to: to_page)
    end.to change { inside.conversations.last.messages.outgoing.count }.by(1)
  end
end
