# frozen_string_literal: true

desc 'Backfill Facebook Messenger contacts (Player … placeholders) for account 2 from Graph API'
task backfill_facebook_profiles: :environment do
  Facebook::BackfillPlayerProfilesService.new.perform
end
