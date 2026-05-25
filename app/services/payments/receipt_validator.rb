# frozen_string_literal: true

module Payments
  class ReceiptValidator
    PROFILE_PAGE_INDICATORS = [
      'your history', 'joined 20', 'not in contacts', 'send money',
      'add to contacts', 'request money', 'view profile'
    ].freeze

    def initialize(ocr_result)
      @ocr = (ocr_result || {}).transform_keys(&:to_s)
    end

    # True only if this looks like a real payment receipt:
    #   - has an amount > 0
    #   - has at least one transaction-evidence field (txn_id OR sender_name+date/time)
    def valid_receipt?
      return false if amount.blank? || amount.to_f <= 0

      has_evidence = transaction_id.present? ||
                     (sender_name.present? && (transaction_date.present? || transaction_time.present?))
      has_evidence
    end

    # True if the image looks like a Cash App / Venmo / Chime contact/profile page
    # rather than a transaction receipt
    def likely_profile_page?
      raw = (@ocr['raw_text'] || '').to_s.downcase
      return false if raw.blank?

      PROFILE_PAGE_INDICATORS.any? { |ind| raw.include?(ind) }
    end

    private

    def amount
      @ocr['amount']
    end

    def transaction_id
      @ocr['transaction_id']
    end

    def sender_name
      @ocr['sender_name']
    end

    def transaction_date
      @ocr['transaction_date']
    end

    def transaction_time
      @ocr['transaction_time']
    end
  end
end
