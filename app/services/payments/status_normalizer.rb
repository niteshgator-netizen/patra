# frozen_string_literal: true

module Payments
  class StatusNormalizer
    FAILED_WORDS   = %w[failed declined rejected denied refused returned blocked reversed bounced unsuccessful].freeze
    CANCELED_WORDS = %w[canceled cancelled void voided].freeze
    PENDING_WORDS  = %w[pending processing in_progress sending sent].freeze
    COMPLETED_WORDS = %w[completed complete success successful confirmed paid received].freeze

    # Returns one of :failed, :canceled, :pending, :completed, :unknown
    def self.normalize(raw)
      s = raw.to_s.downcase.strip
      return :unknown if s.empty?
      return :canceled  if CANCELED_WORDS.any? { |w| s == w || s.include?(w) }
      return :failed    if FAILED_WORDS.any?   { |w| s.include?(w) }
      return :completed if COMPLETED_WORDS.any? { |w| s.include?(w) }
      return :pending   if PENDING_WORDS.any?  { |w| s.include?(w) }

      :unknown
    end

    # OCR statuses that should trigger the email-confirmation pipeline (vs immediate failure routing)
    def self.needs_email_confirmation?(raw)
      [:pending, :completed].include?(normalize(raw))
    end
  end
end
