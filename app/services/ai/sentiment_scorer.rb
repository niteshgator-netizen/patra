# frozen_string_literal: true

module Ai
  class SentimentScorer
    NEGATIVE = %w[angry upset frustrated mad terrible horrible worst scam fraud steal cheat complaint].freeze
    POSITIVE = %w[thanks thank awesome great love excellent perfect amazing wonderful].freeze

    def self.score(messages)
      text = Array(messages).map { |m| m.content.to_s }.join(' ').downcase
      neg = NEGATIVE.count { |w| text.include?(w) }
      pos = POSITIVE.count { |w| text.include?(w) }

      if neg > pos + 1
        'negative'
      elsif pos > neg + 1
        'positive'
      else
        'neutral'
      end
    end
  end
end
