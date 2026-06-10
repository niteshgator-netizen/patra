# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Backup::DripScheduler do
  include ActiveSupport::Testing::TimeHelpers

  let(:account) { create(:account) }
  let(:start_time) { Time.zone.parse('2026-06-01 12:00:00 UTC') }

  def warming_page(stamp: start_time)
    create(:backup_page,
           account: account,
           status: 'warming',
           stats: stamp ? { 'warming_started_at' => stamp.iso8601 } : {},
           health_check_at: Time.current - 1.minute)
  end

  def advance(page)
    described_class.new(backup_page: page).advance_warming
  end

  describe '#advance_warming' do
    {
      0 => ['pre_warm', false],
      1 => ['responding', false],
      2 => ['responding', false],
      3 => ['partial_intro', false],
      6 => ['partial_intro', false],
      7 => ['fully_active', true],
      8 => ['fully_active', true]
    }.each do |day, (expected_phase, expected_promoted)|
      it "resolves day #{day} to #{expected_phase} (promote=#{expected_promoted})" do
        travel_to(start_time + day.days + 1.minute) do
          page = warming_page
          page.update!(health_check_at: Time.current - 1.minute)

          phase = advance(page)

          expect(phase).to eq(expected_phase)
          expect(page.reload.status == 'active').to eq(expected_promoted)
        end
      end
    end

    it 'does not promote at day 7 when the health check is stale' do
      travel_to(start_time + 7.days + 1.minute) do
        page = warming_page
        page.update!(health_check_at: Time.current - 2.hours)

        expect(advance(page)).to eq('fully_active')
        expect(page.reload.status).to eq('warming')
      end
    end

    it 'ignores updated_at touches — the clock runs from the warming stamp' do
      travel_to(start_time + 6.days) do
        page = warming_page
        page.update!(health_check_at: Time.current) # hourly sweep touches updated_at

        expect(advance(page)).to eq('partial_intro')
        expect(page.reload.status).to eq('warming')
      end
    end

    it 'stamps warming_started_at on first run and never overwrites it' do
      page = nil
      travel_to(start_time) do
        page = warming_page(stamp: nil)
        advance(page)
        expect(page.reload.stats['warming_started_at']).to eq(start_time.iso8601)
      end

      travel_to(start_time + 2.days) do
        page.update!(health_check_at: Time.current - 1.minute)
        expect(advance(page)).to eq('responding')
        expect(page.reload.stats['warming_started_at']).to eq(start_time.iso8601)
        expect(page.reload.status).to eq('warming')
      end
    end
  end
end
