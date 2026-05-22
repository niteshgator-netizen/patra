# frozen_string_literal: true

namespace :patra do
  desc 'Manually backfill an inbox from FB. Usage: rake patra:backfill[123]'
  task :backfill, [:inbox_id] => :environment do |_, args|
    inbox_id = args[:inbox_id].to_i
    raise ArgumentError, 'inbox_id required' if inbox_id.zero?

    Patra::FacebookBackfillJob.perform_now(inbox_id)
  end
end
