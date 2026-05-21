module BellaRag
  class ProcessUploadJob < ApplicationJob
    queue_as :low

    def perform(upload_id)
      upload = BellaRagUpload.find(upload_id)
      upload.update!(status: 'processing')

      parser = Bella::TrainingPairParser.new(upload.raw_content)
      pairs = parser.parse

      created = 0
      skipped = 0
      pairs.each do |pair|
        customer = pair[:customer].to_s.strip
        cashier = pair[:cashier].to_s.strip
        next (skipped += 1) if customer.blank? || cashier.blank?
        next (skipped += 1) if BellaRagPair.exists?(account_id: upload.account_id, customer_text: customer)

        begin
          embed_input, embedding = embed_pair(customer)
          BellaRagPair.create!(
            account_id: upload.account_id,
            industry_slug: nil,
            source: 'upload',
            approved: true,
            anonymized: false,
            created_by_user_id: upload.user_id,
            customer_text: customer[0, 4000],
            cashier_text: cashier[0, 4000],
            embed_input: embed_input,
            embedding: embedding,
            embedding_model: Bella::VoyageEmbedder::MODEL
          )
          created += 1
        rescue StandardError => e
          skipped += 1
          Rails.logger.warn("[BellaRagUpload##{upload.id}] skipped pair: #{e.class}: #{e.message[0, 100]}")
        end
      end

      upload.update!(status: 'completed', pairs_created: created, pairs_skipped: skipped)
      Rails.logger.info("[BellaRagUpload##{upload.id}] complete: created=#{created} skipped=#{skipped}")
    rescue StandardError => e
      upload&.update!(status: 'failed', error_message: e.message)
      raise
    end

    private

    def embed_pair(customer_text)
      input = "[customer]: #{customer_text.to_s[0, 4000]}"
      vec = Bella::VoyageEmbedder.embed_one(input, input_type: 'document')
      raise Bella::VoyageEmbedder::EmbeddingError, 'empty embedding' if vec.blank?
      [input, vec]
    end
  end
end
