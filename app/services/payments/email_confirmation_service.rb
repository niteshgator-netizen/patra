# frozen_string_literal: true

module Payments
  class EmailConfirmationService
    MAX_CHECK_ATTEMPTS = 24

    def initialize(contact:)
      @contact = contact
      @account = contact.account
    end

    def check_all
      logs = finance_logs
      checked = 0
      confirmed = 0
      modified = false

      logs.each do |entry|
        next unless entry.is_a?(Hash)
        next unless eligible_for_check?(entry)

        checked += 1
        before_attempts = entry['email_check_attempts'].to_i
        before_confirmed = entry['email_confirmed']

        if check_entry(entry)
          confirmed += 1
        end

        modified = true if entry['email_confirmed'] != before_confirmed ||
                         entry['email_check_attempts'].to_i != before_attempts
      end

      persist_logs!(logs) if modified

      { checked: checked, confirmed: confirmed }
    end

    def check_entry(entry)
      return true if entry['email_confirmed'] == true
      return false unless entry.is_a?(Hash)
      return false unless eligible_for_check?(entry)

      handle = resolve_payment_handle(entry)
      return false unless handle

      match = verify_with_imap(handle, entry)
      if match
        entry['email_confirmed'] = true
        entry['email_confirmed_at'] = Time.current.iso8601
        entry['email_match_source'] = 'imap_poll'
        entry['status_before_email_verify'] = entry['status']
        entry['status'] = 'Verified'
        true
      else
        entry['email_check_attempts'] = entry['email_check_attempts'].to_i + 1
        false
      end
    end

    private

    def finance_logs
      Array(@contact.custom_attributes&.dig('patra_finance_logs')).map do |raw|
        raw.is_a?(Hash) ? raw.stringify_keys : raw
      end
    end

    def persist_logs!(logs)
      attrs = (@contact.custom_attributes || {}).stringify_keys
      attrs['patra_finance_logs'] = logs
      @contact.custom_attributes = attrs
      @contact.save!(touch: false)
    end

    def eligible_for_check?(entry)
      return false if entry['email_confirmed'] == true
      return false unless StatusNormalizer.needs_email_confirmation?(entry['raw_status'])
      return false if entry['email_check_attempts'].to_i >= MAX_CHECK_ATTEMPTS

      resolve_payment_handle(entry).present?
    end

    def resolve_payment_handle(entry)
      platform = entry['platform'].to_s.downcase
      recip = entry['recipient_handle'].to_s.gsub(/^[\$@]/, '').strip.downcase
      return nil if platform.blank? || recip.blank? || @account.blank?

      @account.payment_handles.where(platform: platform).find do |handle|
        handle.normalized_handle == recip
      end
    end

    def verify_with_imap(handle, entry)
      verifier = ImapVerifier.new(payment_handle: handle)
      verifier.verify(
        amount: entry['amount'],
        sender_name: entry['sender_name'],
        transaction_id: entry['transaction_id']
      )
    rescue StandardError => e
      Rails.logger.error(
        "[EmailConfirmationService] IMAP verify failed contact=#{@contact.id} handle=#{handle.id}: #{e.message}"
      )
      false
    end
  end
end
