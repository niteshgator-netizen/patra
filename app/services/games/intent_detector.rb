# Detects load/cashout intents from customer messages.
# Returns { intent:, amount:, game_username: } or nil.
# Used by ConversationOrchestrator.

module Games
  class IntentDetector
    LOAD_PATTERNS = [
      /load\s+(?:me\s+)?\$?(\d+(?:\.\d{1,2})?)/i,
      /add\s+\$?(\d+(?:\.\d{1,2})?)/i,
      /recharge\s+\$?(\d+(?:\.\d{1,2})?)/i,
      /top\s*up\s+\$?(\d+(?:\.\d{1,2})?)/i,
      /deposit\s+\$?(\d+(?:\.\d{1,2})?)/i,
      /load\s+(\d+(?:\.\d{1,2})?)\$?\s+(?:on|to|for|in)\s+([a-z0-9_]{3,20})/i,
      /(\d+(?:\.\d{1,2})?)\s*\$?\s+(?:on|to|for|in)\s+([a-z0-9_]{3,20})/i
    ].freeze

    CASHOUT_PATTERNS = [
      /cash\s*out\s+\$?(\d+(?:\.\d{1,2})?)/i,
      /cashout\s+\$?(\d+(?:\.\d{1,2})?)/i,
      /redeem\s+\$?(\d+(?:\.\d{1,2})?)/i,
      /withdraw\s+\$?(\d+(?:\.\d{1,2})?)/i,
      /payout\s+\$?(\d+(?:\.\d{1,2})?)/i,
      /i\s+(?:want\s+|wanna\s+)?(?:to\s+)?(?:cash\s*out|cashout|redeem|withdraw)/i
    ].freeze

    USERNAME_PATTERNS = [
      /(?:username|user|account|on\s+game\s*vault|on\s+gv|as)\s*:?\s*([a-z0-9_]{3,30})/i,
      /my\s+(?:username|name|user|account)\s+is\s+([a-z0-9_]{3,30})/i,
      /i'?m\s+([a-z0-9_]{3,30})\s+on/i
    ].freeze

    GAME_KEYWORDS = {
      'game_vault' => %w[gamevault game vault gv],
      'orion_stars' => %w[orion orionstars],
      'juwa' => %w[juwa],
      'fire_kirin' => %w[firekirin fire kirin],
      'milky_way' => %w[milkyway milky way]
    }.freeze

    POINTS_PATTERNS = [
      /(?:i\s+have|got|earned|made|got\s+to|hit|at)\s+\$?(\d+(?:\.\d{1,2})?)\s*(?:points?|pts?)?/i,
      /(?:i\s+won|won)\s+\$?(\d+(?:\.\d{1,2})?)/i
    ].freeze

    TIP_PATTERNS = [
      /(?:and\s+)?tip\s+\$?(\d+(?:\.\d{1,2})?)/i
    ].freeze

    RELOAD_PATTERNS = [
      /(?:and\s+)?reload\s+\$?(\d+(?:\.\d{1,2})?)/i,
      /(?:and\s+)?keep\s+\$?(\d+(?:\.\d{1,2})?)\s+in/i
    ].freeze

    CREATE_ACCOUNT_PATTERNS = [
      /create\s+(?:me\s+)?(?:a\s+)?(?:new\s+)?(?:username|user|account|profile|login)/i,
      /make\s+(?:me\s+)?(?:a\s+)?(?:new\s+)?(?:username|user|account)/i,
      /(?:i\s+)?need\s+(?:a\s+)?(?:new\s+)?(?:username|user|account)/i,
      /(?:can\s+you\s+)?sign\s+me\s+up/i,
      /set\s+(?:me\s+)?up\s+(?:a\s+)?(?:new\s+)?(?:account|username)/i,
      /never\s+played\s+(?:before|here)/i,
      /first\s+time\s+(?:playing|here)/i,
      /(?:i\s+)?don'?t\s+have\s+(?:a\s+)?(?:username|account)/i
    ].freeze

    class << self
      def detect(message_text)
        return nil if message_text.blank?

        text = message_text.to_s

        if match_any(text, CREATE_ACCOUNT_PATTERNS)
          {
            intent: :request_account_creation,
            game_slug: detect_game(text) || 'game_vault'
          }
        elsif (m = match_any(text, CASHOUT_PATTERNS))
          {
            intent: :cashout,
            amount: m[1] ? m[1].to_f : nil,
            game_username: extract_username(text),
            game_slug: detect_game(text),
            total_points: extract_points(text),
            tip_amount: extract_tip(text),
            reload_amount: extract_reload(text)
          }
        elsif (m = match_any(text, LOAD_PATTERNS))
          amount = m[1].to_f
          # Some patterns capture username in group 2
          captured_username = m[2] if m.size > 2 && m[2].present?
          {
            intent: :load,
            amount: amount,
            game_username: captured_username || extract_username(text),
            game_slug: detect_game(text) || (captured_username ? 'game_vault' : nil)
          }
        elsif (username = extract_username(text)) && username.length >= 3
          { intent: :username_provided, game_username: username, game_slug: detect_game(text) }
        end
      end

      private

      def match_any(text, patterns)
        patterns.each do |pattern|
          m = text.match(pattern)
          return m if m
        end
        nil
      end

      def extract_username(text)
        USERNAME_PATTERNS.each do |pattern|
          m = text.match(pattern)
          return m[1].downcase if m && m[1] && !common_word?(m[1])
        end
        nil
      end

      def extract_points(text)
        m = match_any(text, POINTS_PATTERNS)
        m && m[1] ? m[1].to_f : nil
      end

      def extract_tip(text)
        m = match_any(text, TIP_PATTERNS)
        m && m[1] ? m[1].to_f : nil
      end

      def extract_reload(text)
        m = match_any(text, RELOAD_PATTERNS)
        m && m[1] ? m[1].to_f : nil
      end

      def detect_game(text)
        lower = text.downcase
        GAME_KEYWORDS.each do |slug, keywords|
          return slug if keywords.any? { |kw| lower.include?(kw) }
        end
        nil
      end

      def common_word?(word)
        %w[load loaded cashout redeem deposit yes no please thanks thx help me you my the and but with from for now today].include?(word.downcase)
      end
    end
  end
end
