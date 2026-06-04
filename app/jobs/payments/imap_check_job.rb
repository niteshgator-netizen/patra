# frozen_string_literal: true

module Payments
  class ImapCheckJob < ApplicationJob
    queue_as :low
    retry_on StandardError, wait: :polynomially_longer, attempts: 3

    MAX_CONTACTS_PER_RUN = 500

    def perform
      lock_key = 'patra:imap_check_job:lock'
      lock_ttl  = 4.minutes.to_i

      acquired = $redis.set(lock_key, 1, nx: true, ex: lock_ttl)
      unless acquired
        Rails.logger.info('[ImapCheckJob] skipped — another instance is running')
        return
      end

      begin
        Account.find_each do |account|
          active_handles = account.payment_handles.where(status: 'active').where.not(verification_email: nil)
          next unless active_handles.exists?

          active_handles.find_each do |ph|
            begin
              Payments::GhostPaymentIngestionService.new(payment_handle: ph).ingest!
            rescue StandardError => e
              error_msg = e.message.to_s
              if error_msg.include?('Too many simultaneous') || error_msg.include?('exceeded') || error_msg.include?('closed stream')
                Rails.logger.warn("[ImapCheckJob] IMAP rate limit hit handle=#{ph.id} — backing off 30s")
                sleep 30
              else
                Rails.logger.error("[ImapCheckJob] ghost_ingest_failed handle=#{ph.id} error=#{error_msg}")
              end
            ensure
              ActiveRecord::Base.connection_pool.release_connection
            end
            sleep 2
          end

          find_contacts_with_unconfirmed_entries(account).each do |contact_id|
            begin
              contact = account.contacts.find_by(id: contact_id) or next
              Payments::EmailConfirmationService.new(contact: contact).check_all
            rescue StandardError => e
              error_msg = e.message.to_s
              if error_msg.include?('Too many simultaneous') || error_msg.include?('exceeded') || error_msg.include?('closed stream')
                Rails.logger.warn("[ImapCheckJob] IMAP rate limit hit contact=#{contact_id} — backing off 30s")
                sleep 30
              else
                Rails.logger.error("[ImapCheckJob] contact #{contact_id} failed: #{error_msg}")
              end
            ensure
              ActiveRecord::Base.connection_pool.release_connection
            end
            sleep 2
          end
        end
        HTTParty.get("https://uptime.betterstack.com/api/v1/heartbeat/m497AzJnPKrBdPJfJbSSKbfR") rescue nil
      ensure
        $redis.del(lock_key) rescue nil
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
