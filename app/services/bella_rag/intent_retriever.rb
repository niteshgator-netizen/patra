# frozen_string_literal: true

# BellaRag::IntentRetriever
# Predicts the real_intent of a customer message by:
#   1. Embedding the text via Voyage AI (query mode)
#   2. Finding top-K most-similar labeled BellaRagPairs via pgvector cosine search
#   3. Weighted-voting on their real_intent labels (weight = cosine similarity)
#   4. Returning { intent:, confidence:, method: 'rag', top_k: [...] } or nil if below threshold
#
# SHADOW MODE ONLY — does not affect any live behavior. Call alongside regex detector,
# log both verdicts. Do NOT route on this output until cutover is approved.
#
module BellaRag
  class IntentRetriever
    CONFIDENCE_THRESHOLD = 0.35   # minimum vote-share to return a result; else nil
    MIN_SIMILARITY       = 0.30   # ignore neighbors with cosine similarity below this
    TOP_K                = 10     # number of neighbors to retrieve
    MAX_TEXT_CHARS       = 512    # truncate input to avoid Voyage rate limits

    # Predict intent for a single customer message.
    # Returns Hash or nil.
    #   { intent: "load_deposit", confidence: 0.87, method: "rag",
    #     top_k: [{ intent: "load_deposit", similarity: 0.91 }, ...] }
    def self.predict(text, account_id: nil, industry_slug: 'sweepstakes')
      return nil if text.blank?

      query_vec = Bella::VoyageEmbedder.embed_one(
        text.to_s.slice(0, MAX_TEXT_CHARS),
        input_type: 'query'
      )
      return nil if query_vec.blank?

      rows = BellaRagPair
               .for_scope(account_id: account_id, industry_slug: industry_slug)
               .where.not(real_intent: nil)
               .nearest_neighbors(:embedding, query_vec, distance: 'cosine')
               .limit(TOP_K)
               .to_a

      return nil if rows.empty?

      # Weighted vote: each neighbor contributes (1 - cosine_distance) to its intent bucket
      votes = Hash.new(0.0)
      top_k_log = []
      rows.each do |row|
        similarity = 1.0 - row.neighbor_distance.to_f
        top_k_log << { intent: row.real_intent, similarity: similarity.round(3) }
        next if similarity < MIN_SIMILARITY
        votes[row.real_intent] += similarity
      end

      return nil if votes.empty?

      total_weight  = votes.values.sum
      best_intent, best_weight = votes.max_by { |_, w| w }
      confidence    = total_weight > 0 ? (best_weight / total_weight).round(3) : 0.0

      return nil if confidence < CONFIDENCE_THRESHOLD

      { intent: best_intent, confidence: confidence, method: 'rag', top_k: top_k_log }
    rescue => e
      Rails.logger.warn("[BellaRag::IntentRetriever] #{e.class}: #{e.message}")
      nil
    end

    # Returns top-K similar RAG pairs as an array of hashes.
    # Used by orchestrator handlers (complaint, tech_issue) for style examples.
    # Different from .predict which returns a single intent label.
    def self.retrieve(text:, account_id:, top_k: 3, threshold: 0.30)
      return [] if text.to_s.strip.empty?

      begin
        query_vec = Bella::VoyageEmbedder.embed_one(text, input_type: 'query')
        return [] if query_vec.blank?

        scope = BellaRagPair.for_scope(account_id: account_id)
                            .where.not(real_intent: nil)

        results = scope.nearest_neighbors(:embedding, query_vec, distance: :cosine)
                       .limit(top_k)
                       .to_a

        results.select { |r| (1 - r.neighbor_distance) >= threshold }.map do |r|
          {
            customer_text: r.customer_text,
            cashier_text: r.cashier_text,
            real_intent: r.real_intent,
            confidence: (1 - r.neighbor_distance).round(4)
          }
        end
      rescue StandardError => e
        Rails.logger.error("[IntentRetriever.retrieve] #{e.class}: #{e.message}")
        []
      end
    end
  end
end
