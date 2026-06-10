# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Sla::CheckViolationsJob do
  subject(:job) { described_class.new }

  let(:account) { create(:account) }
  let(:contact) { create(:contact, account: account) }

  before do
    allow(Audit::TelegramNotifier).to receive(:sla_violation)
    allow(Redis::Alfred).to receive(:get).and_return(nil)
    allow(Redis::Alfred).to receive(:set)
  end

  def open_conversation_with_inbound(age:)
    conversation = create(:conversation, account: account, contact: contact, status: :open)
    create(:message, account: account, conversation: conversation,
                     message_type: :incoming, sender: contact, created_at: age.ago)
    conversation
  end

  it 'skips the account entirely when sla_alerts_enabled is false' do
    account.update!(custom_attributes: { 'sla_alerts_enabled' => false, 'first_response_limit_minutes' => 5 })
    open_conversation_with_inbound(age: 2.hours)

    job.perform

    expect(Audit::TelegramNotifier).not_to have_received(:sla_violation)
  end

  it 'alerts using first_response_limit_minutes from custom_attributes (no policy needed)' do
    account.update!(custom_attributes: { 'first_response_limit_minutes' => 5 })
    open_conversation_with_inbound(age: 10.minutes)

    job.perform

    expect(Audit::TelegramNotifier).to have_received(:sla_violation)
      .with(hash_including(text: include('waiting')))
  end

  it 'does not alert under the custom first-response limit' do
    account.update!(custom_attributes: { 'first_response_limit_minutes' => 30 })
    open_conversation_with_inbound(age: 10.minutes)

    job.perform

    expect(Audit::TelegramNotifier).not_to have_received(:sla_violation)
  end

  it 'alerts once per conversation on resolution_limit_minutes (idempotent stamp)' do
    account.update!(custom_attributes: { 'resolution_limit_minutes' => 60 })
    conversation = open_conversation_with_inbound(age: 2.hours)
    create(:message, account: account, conversation: conversation,
                     message_type: :outgoing, created_at: 119.minutes.ago)

    stamps = {}
    allow(Redis::Alfred).to receive(:get) { |key| stamps[key] }
    allow(Redis::Alfred).to receive(:set) { |key, value, **| stamps[key] = value }

    job.perform
    job.perform

    expect(Audit::TelegramNotifier).to have_received(:sla_violation)
      .with(hash_including(text: include('unresolved'))).once
  end

  it 'does nothing when neither policies nor custom limits exist' do
    open_conversation_with_inbound(age: 2.days)

    job.perform

    expect(Audit::TelegramNotifier).not_to have_received(:sla_violation)
  end
end
