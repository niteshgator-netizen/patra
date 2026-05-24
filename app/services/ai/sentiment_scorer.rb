# frozen_string_literal: true

module Ai
  class SentimentScorer
    POSITIVE = %w[thanks thank great awesome love happy good perfect].freeze
    NEGATIVE = %w[bad angry scam steal refund hate terrible worst fraud attorney].freeze

    def self.score(text)
      return 'neutral' if text.blank?

      down = text.downcase
      return 'negative' if NEGATIVE.any? { |w| down.include?(w) }
      return 'positive' if POSITIVE.any? { |w| down.include?(w) }

      'neutral'
    end
  end
end
