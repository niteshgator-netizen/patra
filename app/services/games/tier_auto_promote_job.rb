# frozen_string_literal: true

module Games
  class TierAutoPromoteJob
    include Sidekiq::Worker
    sidekiq_options queue: :low

    def perform(contact_id)
      contact = Contact.find_by(id: contact_id)
      return unless contact

      Games::TierAutoPromoteService.check(contact: contact)
    end
  end
end
