# Bella RAG (Retrieval-Augmented Generation) corpus.
# One row = one historical customer-cashier exchange we want Bella to learn from.
# The `embedding` column stores a 512-dim Voyage AI vector of `embed_input`.
# Phase 3 will query this table to find similar past conversations at reply time.
class BellaRagPair < ApplicationRecord
  has_neighbors :embedding, dimensions: 512

  scope :for_industry, ->(ind) { where(industry: ind) }
  scope :for_persona,  ->(per) { where(persona: per) }

  # Find the K most-similar historical exchanges to a query string.
  # `query_text` is the live customer message (optionally with prior turns).
  # Returns ActiveRecord::Relation of BellaRagPair rows, ordered by similarity.
  def self.search_similar(query_text, limit: 10, industry: 'sweepstakes', persona: 'bella')
    return BellaRagPair.none if query_text.blank?
    query_vec = Bella::VoyageEmbedder.embed_one(query_text, input_type: 'query')
    return BellaRagPair.none if query_vec.blank?
    for_industry(industry).for_persona(persona)
      .nearest_neighbors(:embedding, query_vec, distance: 'cosine')
      .limit(limit)
  end
end
