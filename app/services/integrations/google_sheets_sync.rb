# frozen_string_literal: true

module Integrations
  class GoogleSheetsSync
    def initialize(account:, spreadsheet_id:)
      @account = account
      @spreadsheet_id = spreadsheet_id
    end

    def export_contacts
      rows = @account.contacts.map do |c|
        [c.id, c.name, c.email, c.phone_number, c.custom_attributes.to_json]
      end
      Rails.logger.info("[GoogleSheetsSync] Exporting #{rows.size} contacts to #{@spreadsheet_id}")
      rows
    end

    def sync_contact(contact)
      Rails.logger.info("[GoogleSheetsSync] Sync contact #{contact.id} to sheet #{@spreadsheet_id}")
    end
  end
end
