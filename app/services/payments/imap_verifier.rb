# frozen_string_literal: true

module Payments
  class ImapVerifier
    def initialize(payment_handle:)
      @handle = payment_handle
    end

    def verify(amount:, sender_name: nil, transaction_id: nil, timestamp: nil)
      fetch_recent_emails.find do |email|
        matches_amount?(email, amount) &&
          matches_sender?(email, sender_name) &&
          matches_transaction?(email, transaction_id)
      end
    end

    def fetch_recent_emails(count: 20)
      return [] if @handle.nil?
      return [] unless @handle.verification_email.present?

      host     = @handle.verification_email_host.to_s.presence || 'imap.gmail.com'
      port     = @handle.verification_email_port || 993
      username = @handle.verification_email
      password = @handle.verification_email_password
      use_ssl  = @handle.verification_email_ssl != false

      Mail.defaults do
        retriever_method :imap, {
          address:    host,
          port:       port,
          user_name:  username,
          password:   password,
          enable_ssl: use_ssl
        }
      end
      Mail.find(what: :last, count: count, order: :desc)
    rescue StandardError => e
      Rails.logger.error("[ImapVerifier] #{e.message}")
      []
    end

    private

    def matches_amount?(email, amount)
      full_body(email).include?(amount.to_s)
    end

    def matches_sender?(email, sender_name)
      return true if sender_name.blank?

      full_body(email).downcase.include?(sender_name.downcase)
    end

    def matches_transaction?(email, transaction_id)
      return true if transaction_id.blank?

      full_body(email).include?(transaction_id.to_s)
    end

    def full_body(email)
      parts = []
      begin
        if email.multipart?
          parts << email.text_part&.decoded if email.text_part
          parts << email.html_part&.decoded if email.html_part
        end
      rescue StandardError
        # fall through
      end
      parts << (email.body.decoded rescue email.body.to_s)
      parts.compact.join(' ').gsub(/<[^>]+>/, ' ').gsub(/&[a-z]+;/i, ' ').gsub(/\s+/, ' ').strip
    rescue StandardError
      email.body.to_s
    end
  end
end
