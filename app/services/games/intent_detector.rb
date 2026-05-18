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
      /(?:username|user)\s*:?\s*([a-z0-9_]{3,30})/i,
      /(?:on\s+game\s*vault|on\s+gv)\s*:?\s*([a-z0-9_]{3,30})/i,
      /my\s+(?:username|name|user|account)\s+is\s+([a-z0-9_]{3,30})/i,
      /i'?m\s+([a-z0-9_]{3,30})\s+on/i
    ].freeze

    GAME_NAME_ALIASES = {
      'juwa' => 'juwa',
      'juwa 2' => 'juwa2',
      'juwa2' => 'juwa2',
      'juwa 2.0' => 'juwa2',
      'game vault' => 'game_vault',
      'gamevault' => 'game_vault',
      'game_vault' => 'game_vault',
      'vegas sweeps' => 'vegas_sweeps',
      'vegas' => 'vegas_sweeps',
      'vegassweeps' => 'vegas_sweeps',
      'vegas_sweeps' => 'vegas_sweeps',
      'vblink' => 'vblink',
      'vb link' => 'vblink',
      'ultra panda' => 'ultra_panda',
      'ultrapanda' => 'ultra_panda',
      'ultra_panda' => 'ultra_panda',
      'panda master' => 'panda_master',
      'pandamaster' => 'panda_master',
      'panda_master' => 'panda_master',
      'gameroom' => 'gameroom',
      'game room' => 'gameroom',
      'cash machine' => 'cash_machine',
      'cashmachine' => 'cash_machine',
      'cash_machine' => 'cash_machine',
      'mafia' => 'mafia',
      'mr all in one' => 'mrallinone',
      'mrallinone' => 'mrallinone',
      'mr_all_in_one' => 'mrallinone',
    }.freeze

    GAME_KEYWORDS = {
      'game_vault' => %w[gamevault game vault gv],
      'orion_stars' => %w[orion orionstars],
      'juwa' => %w[juwa],
      'fire_kirin' => %w[firekirin fire kirin],
      'milky_way' => %w[milkyway milky way],
      'panda_master' => %w[pandamaster panda_master],
      'gameroom' => %w[gameroom game_room],
      'cash_machine' => %w[cashmachine cash_machine],
      'mafia' => %w[mafia],
      'mrallinone' => %w[mrallinone mr_all_in_one]
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

    CASHOUT_METHOD_PATTERNS = [
      /(?:(?:via|to|on|using)\s+)?(?:my\s+)?(?:cashapp|cash\s*app)\s*(?:is\s+|tag\s+|handle\s+|:\s*)?([\$\@]?[a-zA-Z0-9_]{3,30})/i,
      /(?:(?:via|to|on|using)\s+)?(?:my\s+)?(?:chime|venmo|paypal|zelle)\s*(?:is\s+|tag\s+|handle\s+|:\s*)?([\$\@]?[a-zA-Z0-9_.@+]{3,50})/i,
      /send\s+(?:it\s+)?to\s+([\$\@][a-zA-Z0-9_]{3,30})/i
    ].freeze

    CREATE_ACCOUNT_PATTERNS = [
      /create\s+(?:me\s+)?(?:an?\s+)?(?:new\s+)?(?:.+\s+)?(?:username|user|account|profile|login|it)/i,
      /make\s+(?:me\s+)?(?:a\s+)?(?:new\s+)?(?:.+\s+)?(?:username|user|account)/i,
      /(?:i\s+)?need\s+(?:an?\s+)?(?:new\s+)?(?:.+\s+)?(?:username|user|account)/i,
      /(?:can\s+you\s+)?sign\s+me\s+up/i,
      /set\s+(?:me\s+)?up\s+(?:a\s+)?(?:new\s+)?(?:.+\s+)?(?:account|username)/i,
      /never\s+played\s+(?:before|here)/i,
      /first\s+time\s+(?:playing|here)/i,
      /(?:i\s+)?don'?t\s+have\s+(?:a\s+)?(?:username|account)/i,
      /(?:set\s+it\s+up|set\s+me\s+up)/i,
      /give\s+me\s+(?:an?\s+)?(?:new\s+)?(?:.+\s+)?account/i,
      /(?:i\s+)?want\s+(?:an?\s+)?(?:new\s+)?(?:.+\s+)?account/i,
      /(?:i\s+)?(?:want|wanna|need)\s+(?:to\s+)?(?:join|start|play|get\s+(?:in|started))/i,
      /(?:can\s+i\s+)?get\s+(?:me\s+)?(?:a\s+|an\s+)?(?:new\s+)?(?:.+\s+)?(?:username|user|account|profile|login)/i,
      /make\s+(?:me\s+)?(?:a\s+)?(?:brand\s+)?(?:new\s+)?(?:.+\s+)?account/i,
      /(?:hook|set)\s+me\s+up/i
    ].freeze

    # Customer picks a payment method ("paypal", "i'll use venmo", "do you have chime", etc.)
    # Captures the platform name in group 1.
    PAYMENT_METHOD_PICK_PATTERNS = [
      /\A\s*(cashapp|cash\s*app|chime|venmo|paypal|zelle)\s*[!.\?]*\s*\z/i,
      /(?:i'?ll\s+|i\s+wanna\s+|i\s+want\s+to\s+|use\s+|let'?s\s+(?:do\s+)?|try\s+|gimme\s+|with\s+|do\s+)(?:the\s+)?(cashapp|cash\s*app|chime|venmo|paypal|zelle)/i,
      /(?:do\s+(?:you\s+have\s+|you\s+got\s+)?|got\s+|have\s+|got\s+any\s+)(cashapp|cash\s*app|chime|venmo|paypal|zelle)/i,
      /(?:send\s+(?:via\s+|using\s+|on\s+)|pay\s+(?:via\s+|using\s+|on\s+|with\s+))(?:the\s+)?(cashapp|cash\s*app|chime|venmo|paypal|zelle)/i
    ].freeze

    class << self
      def detect(message_text)
        return nil if message_text.blank?

        text = message_text.to_s
        Rails.logger.info("[IntentDetector] checking text=#{text[0..200]}")

        result = (if (create_account = detect_account_creation_request(text))
                    create_account
                  elsif (m = match_any(text, PAYMENT_METHOD_PICK_PATTERNS))
                    raw_platform = m[1].to_s.downcase.gsub(/\s+/, '')
                    normalized = raw_platform == 'cashapp' ? 'cashapp' : raw_platform
                    Rails.logger.info("[IntentDetector] matched payment_method_chosen platform=#{normalized}")
                    {
                      intent: :payment_method_chosen,
                      platform: normalized
                    }
                  elsif (m = match_any(text, CASHOUT_PATTERNS))
                    Rails.logger.info("[IntentDetector] matched cashout amount=#{m[1]}")
                    {
                      intent: :cashout,
                      amount: m[1] ? m[1].to_f : nil,
                      game_username: extract_username(text),
                      game_slug: detect_game(text),
                      cashout_method: extract_cashout_method(text),
                      total_points: extract_points(text),
                      tip_amount: extract_tip(text),
                      reload_amount: extract_reload(text)
                    }
                  elsif (m = match_any(text, LOAD_PATTERNS))
                    amount = m[1].to_f
                    # Some patterns capture username in group 2
                    captured_username = m[2] if m.size > 2 && m[2].present?
                    Rails.logger.info("[IntentDetector] matched load amount=#{m[1]}")
                    {
                      intent: :load,
                      amount: amount,
                      game_username: captured_username || extract_username(text),
                      game_slug: detect_game(text) || (captured_username ? 'game_vault' : nil)
                    }
                  elsif (new_acct = detect_new_account_request_with_game(text))
                    new_acct
                  elsif (username = extract_username(text)) && username.length >= 3
                    Rails.logger.info("[IntentDetector] matched username #{username}")
                    { intent: :username_provided, game_username: username, game_slug: detect_game(text) }
                  end)

        Rails.logger.info("[IntentDetector] result=#{result.inspect}")
        result
      end

      def detect_game(text)
        return nil if text.blank?
        resolved_slug = resolve_game_slug(text)
        return resolved_slug if resolved_slug.present?

        lower = text.to_s.downcase
        GAME_KEYWORDS.each do |slug, keywords|
          return slug if keywords.any? { |kw| lower.include?(kw) }
        end
        nil
      end

      def resolve_game_slug(text)
        return nil if text.nil? || text.to_s.strip.empty?

        normalized = text.to_s.downcase.strip
        GAME_NAME_ALIASES.keys.sort_by { |k| -k.length }.each do |alias_name|
          return GAME_NAME_ALIASES[alias_name] if normalized.include?(alias_name)
        end
        nil
      end

      private

      def detect_account_creation_request(text)
        begin
          return nil if text.blank?
          return nil unless match_any(text, CREATE_ACCOUNT_PATTERNS)

          slug = resolve_game_slug(text)
          Rails.logger.info("[IntentDetector] matched request_account_creation slug=#{slug.inspect}")
          { intent: :request_account_creation, game_slug: slug }
        rescue StandardError => e
          Rails.logger.warn("[IntentDetector] detect_account_creation_request failed: #{e.class}: #{e.message}")
          nil
        end
      end

      # "i need a juwa account" and similar — requires a known game from GAME_KEYWORDS; skips if a
      # probable username token is present so :username_provided can win on combined/latest text.
      def detect_new_account_request_with_game(text)
        begin
          return nil if text.blank?

          slug = resolve_game_slug(text)
          return nil if contains_probable_username_token?(text)
          return nil unless new_account_for_game_phrase?(text)

          Rails.logger.info("[IntentDetector] matched new_account_request_for_game slug=#{slug}")
          { intent: :request_account_creation, game_slug: slug }
        rescue StandardError => e
          Rails.logger.warn("[IntentDetector] detect_new_account_request_with_game failed: #{e.class}: #{e.message}")
          nil
        end
      end

      def game_name_regex_fragment
        @game_name_regex_fragment ||= begin
          keywords = GAME_NAME_ALIASES.keys.sort_by { |k| -k.length }
          keywords.map do |k|
            k.split(/\s+/).map { |part| Regexp.escape(part) }.join('\s+')
          end.join('|')
        end
      end

      def new_account_for_game_phrase?(text)
        norm = text.to_s.downcase.gsub(/\s+/, ' ').strip
        g = game_name_regex_fragment
        patterns = [
          /\bi\s+need\s+a\s+(?:#{g})\s+account\b/,
          /\bi\s+need\s+(?:#{g})\s+account\b/,
          /\bneed\s+a\s+(?:#{g})\s+account\b/,
          /\bneed\s+(?:#{g})\s+account\b/,
          /\bcan\s+i\s+get\s+a\s+(?:#{g})\s+account\b/,
          /\bcan\s+i\s+get\s+(?:#{g})\s+account\b/,
          /\bgive\s+me\s+a\s+(?:#{g})\s+account\b/,
          /\bgive\s+me\s+(?:#{g})\s+account\b/,
          /\bi\s+want\s+a\s+(?:#{g})\s+account\b/,
          /\bi\s+want\s+(?:#{g})\s+account\b/,
          /\bsign\s+me\s+up\s+for\s+(?:#{g})\b/,
          /\bset\s+me\s+up\s+on\s+(?:#{g})\b/,
          /\bcreate\s+a\s+(?:#{g})\s+account\b/,
          /\bmake\s+me\s+a\s+(?:#{g})\s+account\b/,
          /\bnew\s+(?:#{g})\s+account\b/
        ]
        patterns.any? { |p| norm.match?(p) }
      end

      def game_related_token?(tok)
        GAME_KEYWORDS.values.flatten.any? do |kw|
          kw == tok || kw.split(/\s+/).include?(tok)
        end
      end

      def contains_probable_username_token?(text)
        return true if extract_username(text).present?

        lower = text.to_s.downcase
        lower.scan(/\b[a-z0-9_]{4,}\b/).any? do |tok|
          next false if common_word?(tok)
          next false if game_related_token?(tok)

          tok.match?(/\d/)
        end
      end

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

      def extract_cashout_method(text)
        CASHOUT_METHOD_PATTERNS.each do |pattern|
          m = text.match(pattern)
          next unless m && m[1].present?
          handle = m[1].to_s.strip
          platform = if text.downcase.include?('cashapp') || text.downcase.include?('cash app')
                       'cashapp'
                     elsif text.downcase.include?('chime')
                       'chime'
                     elsif text.downcase.include?('venmo')
                       'venmo'
                     elsif text.downcase.include?('paypal')
                       'paypal'
                     elsif text.downcase.include?('zelle')
                       'zelle'
                     else
                       'unknown'
                     end
          return { platform: platform, handle: handle }
        end
        nil
      end

      def common_word?(word)
        reserved = %w[
          load loaded cashout redeem deposit yes no please thanks thx help me you my the and but with from for now today
          game games vault gv orion juwa kirin fire milky way panda sweep vegas cash dragon lightning noble joker room cashier bella patra
          new old username user account password email phone number name
          ans send setup create need want first after that will check lyk did it hey can you
          fast slow good bad quick just also
        ]
        reserved.include?(word.downcase)
      end
    end
  end
end
