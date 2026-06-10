# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Reengagement::ContactCooldown do
  let(:account) { create(:account) }
  let(:contact) { create(:contact, account: account) }

  describe '.window_hours' do
    it 'defaults to 72' do
      expect(described_class.window_hours).to eq(72)
    end

    it 'honors PATRA_REENGAGE_COOLDOWN_HOURS' do
      with_modified_env PATRA_REENGAGE_COOLDOWN_HOURS: '100' do
        expect(described_class.window_hours).to eq(100)
      end
    end

    it 'never silently disables itself on garbage values' do
      with_modified_env PATRA_REENGAGE_COOLDOWN_HOURS: 'banana' do
        expect(described_class.window_hours).to eq(72)
      end
      with_modified_env PATRA_REENGAGE_COOLDOWN_HOURS: '-5' do
        expect(described_class.window_hours).to eq(72)
      end
    end
  end

  describe 'shared stamp across senders' do
    it 'blocks every sender once any sender stamps' do
      described_class.stamp!(contact)

      expect(described_class.on_cooldown?(contact.reload)).to be(true)
    end

    it 'frees the contact after the window passes' do
      contact.update!(custom_attributes: { described_class::KEY => 73.hours.ago.utc.iso8601 })

      expect(described_class.on_cooldown?(contact)).to be(false)
    end

    it 'makes Contacts::ReEngageJob skip a contact stamped by another sender' do
      contact.update!(custom_attributes: {
                        'juwa_username' => 'p1',
                        described_class::KEY => Time.now.utc.iso8601
                      })
      conversation = create(:conversation, account: account, contact: contact)

      expect(Messages::MessageBuilder).not_to receive(:new)

      job = Contacts::ReEngageJob.new
      job.send(:send_reengage, account, contact.reload, 'hey!')

      expect(conversation.messages.outgoing.count).to eq(0)
    end
  end
end
