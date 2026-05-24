# frozen_string_literal: true

class KnowledgeArticle < ApplicationRecord
  belongs_to :account
  belongs_to :created_by_user, class_name: 'User', optional: true

  validates :title, :content, presence: true

  scope :published, -> { where(published: true) }
  scope :for_category, ->(cat) { where(category: cat) }

  def helpfulness_score
    total = helpful_count + not_helpful_count
    return 0 if total.zero?

    ((helpful_count.to_f / total) * 100).round(1)
  end

  def record_feedback!(helpful:)
    if helpful
      increment!(:helpful_count)
    else
      increment!(:not_helpful_count)
    end
  end
end
