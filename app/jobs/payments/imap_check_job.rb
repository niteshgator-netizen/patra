# frozen_string_literal: true

module Payments
  class ImapCheckJob < ApplicationJob
    queue_as :scheduled_jobs
    retry_on StandardError, wait: :polynomially_longer, attempts: 3

    MAX_CONTACTS_PER_RUN = 500

    def perform
      Account.find_each do |account|
        next unless account.payment_handles.where.not(verification_email: nil).exists?

        account.payment_handles.where.not(verification_email: nil).where(status: 'active').find_each do |ph|
          Payments::GhostPaymentIngestionService.new(payment_handle: ph).ingest!
        rescue StandardError => e
          Rails.logger.error("[ImapCheckJob] ghost_ingest_failed handle=#{ph.id} error=#{e.message}")
        end

        find_contacts_with_unconfirmed_entries(account).each do |contact_id|
          contact = account.contacts.find_by(id: contact_id) or next
          Payments::EmailConfirmationService.new(contact: contact).check_all
        rescue StandardError => e
          Rails.logger.error("[ImapCheckJob] contact #{contact_id} failed: #{e.message}")
        end
      end
    end

    private

    def find_contacts_with_unconfirmed_entries(account)
      ids = []

      account.contacts
             .where("custom_attributes ? 'patra_finance_logs'")
             .find_each do |contact|
        break if ids.size >= MAX_CONTACTS_PER_RUN

        logs = Array(contact.custom_attributes['patra_finance_logs'])
        next unless logs.any? { |entry| unconfirmed_entry?(entry) }

        ids << contact.id
      end

      ids
    end

    def unconfirmed_entry?(entry)
      return false unless entry.is_a?(Hash)

      entry['email_confirmed'] != true &&
        StatusNormalizer.needs_email_confirmation?(entry['raw_status']) &&
        entry['email_check_attempts'].to_i < EmailConfirmationService::MAX_CHECK_ATTEMPTS
    end
  end
end
