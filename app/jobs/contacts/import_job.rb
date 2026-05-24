# frozen_string_literal: true

module Contacts
  class ImportJob < ApplicationJob
    queue_as :low
    retry_on StandardError, wait: :polynomially_longer, attempts: 3

    def perform(account_id, csv_data, column_mapping)
      account = Account.find(account_id)
      require 'csv'
      rows = CSV.parse(csv_data, headers: true)
      imported = 0
      skipped = 0

      rows.each do |row|
        phone = row[column_mapping['phone']]
        email = row[column_mapping['email']]

        if phone.present? && account.contacts.exists?(phone_number: phone)
          skipped += 1
          next
        end
        if email.present? && account.contacts.exists?(email: email)
          skipped += 1
          next
        end

        account.contacts.create!(
          name: row[column_mapping['name']],
          phone_number: phone,
          email: email,
          custom_attributes: { game_usernames: row[column_mapping['game_usernames']] }
        )
        imported += 1
      end

      { imported: imported, skipped: skipped }
    end
  end
end
