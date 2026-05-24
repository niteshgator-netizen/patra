# frozen_string_literal: true

module Payments
  class ImapVerifier
    def initialize(payment_handle:)
      @handle = payment_handle
    end

    def verify(amount:, sender_name: nil, transaction_id: nil, timestamp: nil)
      emails = fetch_recent_emails
      emails.find do |email|
        matches_amount?(email, amount) &&
          matches_sender?(email, sender_name) &&
          matches_transaction?(email, transaction_id)
      end
    end

    private

    def fetch_recent_emails
      return [] unless @handle.verification_email.present?

      Mail.defaults do
        retriever_method :imap, {
          address: @handle.verification_email_host,
          port: 993,
          user_name: @handle.verification_email,
          password: @handle.verification_email_password,
          enable_ssl: true
        }
      end
      Mail.find(what: :last, count: 20, order: :desc)
    rescue StandardError => e
      Rails.logger.error("[ImapVerifier] #{e.message}")
      []
    end

    def matches_amount?(email, amount)
      email.body.to_s.include?(amount.to_s)
    end

    def matches_sender?(email, sender_name)
      return true if sender_name.blank?

      email.body.to_s.downcase.include?(sender_name.downcase)
    end

    def matches_transaction?(email, transaction_id)
      return true if transaction_id.blank?

      email.body.to_s.include?(transaction_id.to_s)
    end
  end
end
