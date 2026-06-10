# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Backup::HealthCheckJob do
  subject(:job) { described_class.new }

  let(:account) { create(:account) }

  before do
    allow(Games::TelegramNotifier).to receive(:api_error).and_return({ ok: true })
  end

  describe '#perform' do
    it 'marks an unhealthy non-active page banned and alerts via the public api_error' do
      page = create(:backup_page, account: account, status: 'warming', position: 1)
      allow(job).to receive(:can_send?).and_return(false)

      expect { job.perform }.not_to raise_error

      expect(page.reload.status).to eq('banned')
      expect(Games::TelegramNotifier).to have_received(:api_error)
        .with(account: account, message: include(page.page_name), details: include(page.page_id))
    end

    it 'continues the sweep past a page whose check raises' do
      crasher = create(:backup_page, account: account, status: 'warming', position: 1)
      survivor = create(:backup_page, account: account, status: 'warming', position: 2)

      allow(job).to receive(:can_send?) do |checked|
        raise StandardError, 'boom' if checked.id == crasher.id

        false
      end

      expect { job.perform }.not_to raise_error

      expect(survivor.reload.status).to eq('banned')
      expect(Games::TelegramNotifier).to have_received(:api_error).once
    end

    it 'does not let a Telegram failure crash the sweep' do
      first = create(:backup_page, account: account, status: 'warming', position: 1)
      second = create(:backup_page, account: account, status: 'warming', position: 2)
      allow(job).to receive(:can_send?).and_return(false)
      allow(Games::TelegramNotifier).to receive(:api_error).and_raise(StandardError, 'telegram down')

      expect { job.perform }.not_to raise_error

      expect(first.reload.status).to eq('banned')
      expect(second.reload.status).to eq('banned')
    end
  end
end
