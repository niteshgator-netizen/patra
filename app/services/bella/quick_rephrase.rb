require 'net/http'
require 'json'

module Bella
  # One-shot Grok call to rephrase a matched cashier reply for the current customer.
  # Returns the rephrased text or nil on any failure (fails CLOSED).
  class QuickRephrase
    XAI_URL    = Ai::ReplyService::XAI_URL
    MODEL      = ENV.fetch('XAI_MODEL', 'grok-4.3').freeze
    MAX_TOKENS = 200
    TIMEOUT    = 15

    class RephraseError < StandardError; end

    def self.call(customer_text:, hint_reply:, conversation_id: nil)
      api_key = ENV['XAI_API_KEY'].to_s
      return nil if api_key.empty?
      return nil if customer_text.to_s.strip.empty?
      return nil if hint_reply.to_s.strip.empty?

      system_prompt = build_prompt(customer_text: customer_text, hint_reply: hint_reply)

      uri = URI(XAI_URL)
      req = Net::HTTP::Post.new(uri, {
        'Authorization' => "Bearer #{api_key}",
        'Content-Type'  => 'application/json',
      })
      req.body = JSON.dump({
        model: MODEL,
        max_tokens: MAX_TOKENS,
        messages: [
          { role: 'system', content: system_prompt },
          { role: 'user', content: customer_text.to_s[0, 800] },
        ],
      })

      res = Net::HTTP.start(uri.hostname, uri.port, use_ssl: true, read_timeout: TIMEOUT) { |h| h.request(req) }
      unless res.code == '200'
        Rails.logger.warn("[AiReply][QuickRephrase] HTTP #{res.code} conv=#{conversation_id} body=#{res.body[0, 200]}")
        return nil
      end
      text = JSON.parse(res.body).dig('choices', 0, 'message', 'content')
      return nil if text.to_s.strip.empty?

      text.strip
    rescue StandardError => e
      Rails.logger.warn("[AiReply][QuickRephrase] failed conv=#{conversation_id} err=#{e.class}: #{e.message[0, 200]}")
      nil
    end

    def self.build_prompt(customer_text:, hint_reply:)
      <<~PROMPT
        YOU ARE BELLA — a real human game loader. You are NOT an AI. You are texting from your phone.

        A customer just said: "#{customer_text}"

        Here's how Bella has actually answered a very similar message before:
        ---
        #{hint_reply}
        ---

        Write a SINGLE reply that:
        - Sounds EXACTLY like the example above — same tone, slang, abbreviations, emojis (or absence of emojis)
        - Fits THIS customer's exact message naturally
        - Max 1-2 short lines, lowercase OK
        - Use natural cashier abbreviations: lmc, fp, k, dear, love, etc.
        - DO NOT invent facts (game balances, usernames, payment handles) — if the example has specifics, only keep them if they generalize
        - DO NOT start with "Certainly" or "Sure thing!" — never sound like a chatbot
        - NEVER admit to being an AI

        Output ONLY the reply text. Nothing else. No quotes around it.
      PROMPT
    end
    private_class_method :build_prompt
  end
end
