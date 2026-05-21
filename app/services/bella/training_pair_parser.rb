module Bella
  class TrainingPairParser
    def initialize(raw_content)
      @raw = raw_content.to_s
    end

    def parse
      data = JSON.parse(@raw)
      messages = extract_messages(data)
      pair_messages(messages)
    rescue JSON::ParserError => e
      Rails.logger.warn("[Bella::TrainingPairParser] JSON parse failed: #{e.message[0, 100]}")
      []
    end

    private

    def extract_messages(data)
      msgs = data['messages'] || data[:messages] || []
      msgs.sort_by { |m| m['timestamp_ms'].to_i }
    end

    def pair_messages(messages)
      pairs = []
      messages.each_cons(2) do |a, b|
        next unless a['content'] && b['content']
        pairs << { customer: a['content'].to_s, cashier: b['content'].to_s }
      end
      pairs
    end
  end
end
