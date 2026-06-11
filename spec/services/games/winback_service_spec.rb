# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Games::WinbackService do
  let(:account) { create(:account) }
  let(:inbox) { create(:inbox, account: account) }
  let(:contact) { create(:contact, account: account) }
  let!(:conversation) { create(:conversation, account: account, inbox: inbox, contact: contact) }
  let(:pref) do
    ReplyPreference.for_account(account.id).tap { |p| p.update!(winback_enabled: true) }
  end
  let(:service) { described_class.new }

  let(:ai_json) { '{"diagnosis":"drifted off","message":"hey, miss you at the tables — fp on me tonight?"}' }

  before do
    allow(Ai::DeepseekClient).to receive(:complete).and_return(ai_json)
    allow(Games::TelegramNotifier).to receive(:winback_manual_alert).and_return({ ok: true })
    allow(Games::TelegramNotifier).to receive(:human_escalation)
  end

  def make_dormant(days)
    create(:message, account: account, inbox: inbox, conversation: conversation,
                     message_type: :incoming, content: 'last one', created_at: days.days.ago)
  end

  describe '#winback_contact' do
    it 'skips players who never engaged (no inbound, no game actions)' do
      expect(service.winback_contact(account, contact, pref)).to be false
      expect(Ai::DeepseekClient).not_to have_received(:complete)
    end

    it 'skips players still inside their dormancy window' do
      make_dormant(2) # regular tier default window = 14 days

      expect(service.winback_contact(account, contact, pref)).to be false
    end

    it 'delivers <=7d dormant players via a normal winback-flagged outgoing message' do
      pref.update!(winback_dormant_days_regular: 3)
      make_dormant(5)

      expect(service.winback_contact(account, contact, pref)).to be true

      # reorder, not order: Message carries a default created_at ASC scope, so
      # .order(desc) appends (ASC wins) and .first would return the OLDEST message.
      msg = conversation.messages.where(private: false).reorder(created_at: :desc).first
      expect(msg.content).to include('miss you at the tables')
      expect(msg.additional_attributes['winback']).to be true
      expect(Games::TelegramNotifier).not_to have_received(:winback_manual_alert)
    end

    it 'delivers >7d dormant players via telegram + private note, never a public message' do
      make_dormant(20)
      public_before = conversation.messages.where(private: false).count

      expect(service.winback_contact(account, contact, pref)).to be true

      expect(Games::TelegramNotifier).to have_received(:winback_manual_alert)
        .with(hash_including(message: a_string_matching(/miss you/), days_dormant: 20))
      expect(conversation.messages.where(private: false).count).to eq(public_before)
      note = conversation.messages.where(private: true).last
      expect(note.content).to include('manual send')
    end

    it 'is idempotent — a second run inside the window sends nothing' do
      make_dormant(20)
      expect(service.winback_contact(account, contact, pref)).to be true

      expect(service.winback_contact(account, contact.reload, pref)).to be false
      expect(Games::TelegramNotifier).to have_received(:winback_manual_alert).once
    end

    it 'respects the shared automated-contact cooldown' do
      make_dormant(20)
      allow(Reengagement::ContactCooldown).to receive(:on_cooldown?).and_return(true)

      expect(service.winback_contact(account, contact, pref)).to be false
      expect(Games::TelegramNotifier).not_to have_received(:winback_manual_alert)
    end

    it 'sends nothing when the AI returns nothing' do
      make_dormant(20)
      allow(Ai::DeepseekClient).to receive(:complete).and_return(nil)

      expect(service.winback_contact(account, contact, pref)).to be false
      expect(Games::TelegramNotifier).not_to have_received(:winback_manual_alert)
    end

    it 'does not stamp the contact when telegram delivery fails' do
      make_dormant(20)
      allow(Games::TelegramNotifier).to receive(:winback_manual_alert).and_raise(StandardError, 'tg down')

      expect(service.winback_contact(account, contact, pref)).to be false
      expect(contact.reload.custom_attributes.to_h['winback_last_contacted_at']).to be_nil
    end
  end

  describe '#parse_ai_output' do
    it 'parses clean JSON' do
      out = service.send(:parse_ai_output, ai_json)
      expect(out[:message]).to include('miss you')
      expect(out[:diagnosis]).to eq('drifted off')
    end

    it 'strips markdown fences' do
      out = service.send(:parse_ai_output, "```json\n#{ai_json}\n```")
      expect(out[:message]).to include('miss you')
    end

    it 'falls back to raw-as-message on broken JSON' do
      out = service.send(:parse_ai_output, 'hey come back and play!')
      expect(out[:message]).to eq('hey come back and play!')
      expect(out[:diagnosis]).to be_nil
    end

    it 'returns nil message on blank input' do
      expect(service.send(:parse_ai_output, nil)[:message]).to be_nil
    end
  end

  describe '#dormancy_days_for' do
    it 'uses per-tier windows from the preference row' do
      pref.update!(winback_dormant_days_vip: 2, winback_dormant_days_regular: 10, winback_dormant_days_new: 5)
      vip_tier = create(:player_tier, account: account, name: 'vip')
      contact.update!(player_tier_id: vip_tier.id)

      expect(service.send(:dormancy_days_for, contact.reload, pref)).to eq(2)

      contact.update!(player_tier_id: nil)
      expect(service.send(:dormancy_days_for, contact.reload, pref)).to eq(10)
    end
  end

  describe '#run_all' do
    it 'only processes accounts with winback enabled' do
      pref.update!(winback_enabled: false)
      expect_any_instance_of(described_class).not_to receive(:run_for_account)

      described_class.run_all
    end
  end
end
