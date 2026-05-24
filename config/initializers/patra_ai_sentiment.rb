# frozen_string_literal: true

ActiveSupport::Reloader.to_prepare do
  Message.class_eval do
    after_create_commit :patra_score_sentiment, if: :incoming?

    def patra_score_sentiment
      score = Ai::SentimentScorer.score(content)
      attrs = content_attributes || {}
      attrs['sentiment'] = score
      update_column(:content_attributes, attrs)
    end
  end
end
