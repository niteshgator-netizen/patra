module BellaRag
  class IngestCandidateJob < ApplicationJob
    queue_as :low

    def perform(candidate_id)
      cand = BellaTakeoverCandidate.find(candidate_id)
      return unless cand.status == 'auto_added'

      return if BellaRagPair.exists?(account_id: cand.account_id, customer_text: cand.customer_text)

      embed_input = "[customer]: #{cand.customer_text[0, 4000]}"
      embedding = Bella::VoyageEmbedder.embed_one(embed_input, input_type: 'document')
      raise Bella::VoyageEmbedder::EmbeddingError, 'empty embedding' if embedding.blank?

      pair = BellaRagPair.create!(
        account_id: cand.account_id,
        industry_slug: nil,
        source: 'human_takeover',
        approved: true,
        anonymized: false,
        customer_text: cand.customer_text,
        cashier_text: cand.human_reply,
        embed_input: embed_input,
        embedding: embedding,
        embedding_model: Bella::VoyageEmbedder::MODEL
      )

      cand.update!(resulting_pair_id: pair.id)
    rescue StandardError => e
      Rails.logger.warn("[BellaRag::IngestCandidateJob#perform] cand_id=#{candidate_id} #{e.class}: #{e.message[0, 200]}")
      raise
    end
  end
end
