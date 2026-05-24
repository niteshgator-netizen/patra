# frozen_string_literal: true

module Industry
  class SweepstakesScript
    VOCABULARY = {
      'deposit' => 'load',
      'withdrawal' => 'cashout',
      'withdraw' => 'cashout',
      'account id' => 'username',
      'gambling' => 'entertainment',
      'betting' => 'playing',
      'wagering' => 'playing'
    }.freeze

    COMPLIANCE_PHRASE = 'for entertainment purposes only'.freeze
    ESCALATION_TRIGGERS = %w[refund scam steal attorney lawyer sue fraud].freeze

    def self.sanitize(text)
      return text if text.blank?

      result = text.dup
      VOCABULARY.each { |from, to| result.gsub!(/\b#{from}\b/i, to) }
      result
    end

    def self.needs_escalation?(text)
      down = text.to_s.downcase
      ESCALATION_TRIGGERS.any? { |t| down.include?(t) }
    end

    def self.compliance_footer
      COMPLIANCE_PHRASE
    end
  end
end
