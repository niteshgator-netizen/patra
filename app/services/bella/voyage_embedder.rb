require 'net/http'
require 'json'

module Bella
  # Thin Voyage AI embeddings client. Free tier: 200M tokens/month.
  # voyage-3-lite -> 512-dimension, L2-normalized vectors (cosine == dot product).
  # https://docs.voyageai.com/reference/embeddings-api
  class VoyageEmbedder
    API_URL    = 'https://api.voyageai.com/v1/embeddings'.freeze
    MODEL      = 'voyage-3-lite'.freeze
    DIMENSIONS = 512
    BATCH_SIZE = 128
    MAX_RETRIES = 3
    READ_TIMEOUT = 60

    class EmbeddingError < StandardError; end

    # Embed an array of strings. Returns array-of-vectors, same order as input.
    # input_type: 'document' for seeding the corpus, 'query' for retrieval.
    def self.embed(texts, input_type: 'document')
      texts = Array(texts).reject(&:blank?)
      return [] if texts.empty?

      api_key = ENV['VOYAGE_API_KEY']
      raise EmbeddingError, 'VOYAGE_API_KEY not set' if api_key.to_s.strip.empty?

      results = []
      texts.each_slice(BATCH_SIZE) do |batch|
        results.concat(call_api(batch, api_key, input_type))
      end
      results
    end

    def self.embed_one(text, input_type: 'query')
      out = embed([text], input_type: input_type)
      out.first
    end

    def self.call_api(batch, api_key, input_type)
      attempts = 0
      begin
        attempts += 1
        uri = URI(API_URL)
        req = Net::HTTP::Post.new(uri, {
          'Authorization' => "Bearer #{api_key}",
          'Content-Type'  => 'application/json',
        })
        req.body = JSON.dump({
          input: batch,
          model: MODEL,
          input_type: input_type,
        })

        res = Net::HTTP.start(uri.hostname, uri.port, use_ssl: true, read_timeout: READ_TIMEOUT) do |h|
          h.request(req)
        end

        case res.code
        when '200'
          JSON.parse(res.body)['data'].sort_by { |d| d['index'] }.map { |d| d['embedding'] }
        when '429', '500', '502', '503', '504'
          raise EmbeddingError, "Voyage transient #{res.code}: #{res.body[0, 200]}"
        else
          raise EmbeddingError, "Voyage permanent #{res.code}: #{res.body[0, 300]}"
        end
      rescue EmbeddingError => e
        if e.message.include?('transient') && attempts < MAX_RETRIES
          sleep(2 ** attempts)
          retry
        end
        raise
      rescue Net::ReadTimeout, Net::OpenTimeout, Errno::ECONNRESET => e
        if attempts < MAX_RETRIES
          sleep(2 ** attempts)
          retry
        end
        raise EmbeddingError, "Voyage network: #{e.class}: #{e.message}"
      end
    end
    private_class_method :call_api
  end
end
