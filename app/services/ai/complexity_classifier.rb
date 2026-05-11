# frozen_string_literal: true

module Ai
  class ComplexityClassifier
    GREETING_RE     = /^(hi+|hey+|hello+|yo+|sup+|wassup+|wasup+|wsg|wsp|gm|gn|good\s+(morning|afternoon|evening|night))[!.?\s]*$/i
    ACK_RE          = /^(thanks?|thx|ty|tysm|ok+|okay|cool|got\s+it|alright|aight|k+|word|bet|lol|lmao|haha+|hehe|nice)[!.?\s]*$/i
    MONEY_RE        = /(\$|usd|dollar|deposit|cashout|cash\s?out|withdraw|load|send|payment|pay\s?me|paid|bonus|free\s?play|refund)/i
    PAYMENT_RE      = /(cash\s?app|cashapp|paypal|chime|venmo|varo|boltpay|zelle|apple\s?pay)/i
    GAME_RE         = /(juwa|firekirin|fire\s?kirin|orionstar|orion\s?star|milkyway|milky\s?way|gamevault|game\s?vault|gameroom|game\s?room|moolah|casino\s?ignite|vegas\s?sweeps|panda\s?master|pandamaster|spin\s?city|vblink|v\s?blink|mafia|cash\s?machine|ultra\s?panda|ultrapanda|billion\s?balls|yolo|vegas\s?roll|cash\s?frenzy|mr\s?all\s?in\s?one)/i
    ESCALATION_RE   = /(manager|human|real\s?person|representative|supervisor|scam|fraud|wtf|stupid|trash|cheat|liar|refund|complain|angry|sue|lawyer)/i
    USERNAME_RE     = /\b[a-z]{2,}\d{2,}\b/i
    EMOJI_ONLY_RE   = /\A(?:\p{Emoji}|\s)+\z/

    def self.classify(message_body, has_attachment: false)
      return :has_image if has_attachment

      body = message_body.to_s.strip
      return :simple if body.empty?

      # Complex checks FIRST (these override simple matches)
      return :complex if body.include?('?')
      return :complex if body.match?(MONEY_RE)
      return :complex if body.match?(PAYMENT_RE)
      return :complex if body.match?(GAME_RE)
      return :complex if body.match?(ESCALATION_RE)
      return :complex if body.match?(USERNAME_RE)
      return :complex if body.split.size > 15

      # Simple checks
      return :simple if body.match?(GREETING_RE)
      return :simple if body.match?(ACK_RE)
      return :simple if body.match?(EMOJI_ONLY_RE)
      return :simple if body.length <= 4
      return :simple if body.split.size == 1 && body.length <= 8 && body !~ /\d/

      # Default safer to over-route to Grok (smart) than under-route
      :complex
    end
  end
end
