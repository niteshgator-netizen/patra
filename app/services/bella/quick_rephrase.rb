module Bella
  # One-shot LLM call to rephrase a matched cashier reply for the current customer.
  # Returns the rephrased text or nil on any failure (fails CLOSED).
  # TAB A: ported from retired Grok/xAI (Batch C) to the shared DeepseekClient -
  # the live brain. Enabling BELLA_RAG_SHORTCUT_ENABLED previously could never
  # produce a reply (xAI credits exhausted -> always nil -> fallthrough).
  class QuickRephrase
    # deepseek-v4-flash spends max_tokens on reasoning+answer combined - too low
    # starves the answer to empty (proven on the main reply path, which uses 800).
    MAX_TOKENS = 800

    class RephraseError < StandardError; end

    def self.call(customer_text:, hint_reply:, conversation_id: nil)
      return nil if customer_text.to_s.strip.empty?
      return nil if hint_reply.to_s.strip.empty?

      system_prompt = build_prompt(customer_text: customer_text, hint_reply: hint_reply)

      text = Ai::DeepseekClient.complete(
        system_prompt: system_prompt,
        user_content: customer_text.to_s[0, 800],
        max_tokens: MAX_TOKENS
      )
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
