# frozen_string_literal: true

# Backfills Messenger contacts that were created with placeholder "Player …" names
# using the Facebook Graph API (name + profile picture).
module Facebook
  class BackfillPlayerProfilesService
    DEFAULT_ACCOUNT_ID = 2

    def initialize(account_id: DEFAULT_ACCOUNT_ID, page_access_token: ENV['FB_PAGE_ACCESS_TOKEN'], io: $stdout)
      @account_id = account_id
      @page_access_token = page_access_token.to_s
      @io = io
    end

    def perform
      if @page_access_token.blank?
        @io.puts 'Skipping Facebook profile backfill: FB_PAGE_ACCESS_TOKEN is not set'
        return
      end

      contacts_scope.find_each do |contact|
        backfill_one(contact)
      end
    end

    private

    def contacts_scope
      Contact.where(account_id: @account_id)
             .where.not(identifier: [nil, ''])
             .where('contacts.name ILIKE ?', 'Player %')
    end

    def backfill_one(contact)
      psid = contact.identifier.to_s.strip
      return if psid.blank?

      profile = GraphProfileService.fetch_profile(psid, page_access_token: @page_access_token)
      new_name = profile[:name].presence
      return if new_name.blank?

      old_name = contact.name

      contact.update!(name: new_name)

      pic = profile[:profile_pic].presence
      Avatar::AvatarFromUrlJob.perform_later(contact, pic) if pic.present?

      @io.puts "Updated: #{old_name} -> #{new_name}"
    end
  end
end
