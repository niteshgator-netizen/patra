# Bella RAG (Retrieval-Augmented Generation) corpus.
# One row = one historical customer-cashier exchange we want Bella to learn from.
# The `embedding` column stores a 512-dim Voyage AI vector of `embed_input`.
# Phase 3 will query this table to find similar past conversations at reply time.
class BellaRagPair < ApplicationRecord
  has_neighbors :embedding, dimensions: 512

  scope :for_industry, ->(ind) { where(industry: ind) }
  scope :for_persona,  ->(per) { where(persona: per) }

  # Convenience: chitchat-only rows (action_type IS NULL)
  scope :chitchat, -> { where(action_type: nil) }

  # Returns Array of {pair: BellaRagPair, distance: Float} sorted by distance ASC.
  # Distance is cosine distance from the neighbor gem (lower = more similar).
  # Caller MUST pass query_vec to avoid re-embedding when the embed is cached.
  def self.search_similar_with_distance(query_vec:, limit: 5, industry: 'sweepstakes', persona: 'bella')
    return [] if query_vec.blank?

    rows = for_industry(industry).for_persona(persona)
             .nearest_neighbors(:embedding, query_vec, distance: 'cosine')
             .limit(limit)
    rows.map { |r| { pair: r, distance: r.neighbor_distance } }
  end

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
