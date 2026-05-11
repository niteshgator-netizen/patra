# frozen_string_literal: true

module Players
  # Parses customer messages (via Chatwoot bridge API) and merges structured
  # player fields into contact custom_attributes. Idempotent per message id
  # using `player_vault_cursor_message_id`.
  class ProfileService
    HTTP_TIMEOUT = 30
    CURSOR_KEY = 'player_vault_cursor_message_id'
    BACKFILL_INCOMING_LIMIT = 15

    PLATFORM_ALIASES = {
      'juwa' => 'juwa', 'juwa 2' => 'juwa', 'juwa 2.0' => 'juwa',
      'fire kirin' => 'firekirin', 'firekirin' => 'firekirin',
      'orionstar' => 'orionstar', 'milkyway' => 'milkyway', 'milky way' => 'milkyway',
      'gamevault' => 'gamevault', 'game vault' => 'gamevault',
      'gameroom' => 'gameroom', 'moolah' => 'moolah',
      'pandamaster' => 'pandamaster', 'panda master' => 'pandamaster',
      'vblink' => 'vblink', 'vegas sweeps' => 'vegas_sweeps', 'vegassweeps' => 'vegas_sweeps',
      'ultra panda' => 'ultra_panda', 'cash machine' => 'cash_machine',
      'casino ignite' => 'casino_ignite', 'spin city' => 'spin_city'
    }.freeze

    PAYMENT_ALIASES = {
      /\bcash\s*app\b|\bcashapp\b/i => 'cashapp',
      /\bvenmo\b/i => 'venmo',
      /\bpaypal\b/i => 'paypal',
      /\bchime\b/i => 'chime'
    }.freeze

    # Narrow enough to avoid "sent a screenshot" while still catching "sent $20".
    DEPOSIT_CONTEXT = /
      (?:
        deposit(?:ed|s)?|
        loaded|
        add(?:ed)?\s+funds|
        put\s+in|
        \b(?:paid|sent)\s+\$
      )
    /ix

    CASHOUT_INTENT = /
      (?:
        want\s+to\s+cash\s*out|
        need\s+to\s+cash\s*out|
        wanna\s+cash\s*out|
        cash\s*out|
        cashing\s+out|
        redeem|
        withdrawal|
        withdraw
      )
    /ix

    CASHOUT_DONE = /
      (?:
        cashed\s+out|
        got\s+my\s+cash\s*out|
        received\s+(?:my\s+)?(?:payout|cash\s*out)|
        money\s+hit\s+(?:my\s+)?(?:cashapp|venmo|paypal|chime)
      )
    /ix


    def initialize(conversation_id:, account_id: nil)
      @conversation_id = conversation_id
      @bridge_account_id = account_id
    end

    def sync!
      return if @conversation_id.blank?
      return if chatwoot_token.blank?

      conv = get_conversation
      return if conv.blank?

      contact_id = conv.dig('meta', 'sender', 'id')
      return if contact_id.blank?

      contact = get_contact(contact_id)
      return if contact.blank?

      payload = fetch_messages_payload
      return if payload.blank?

      attrs = stringify_keys(contact['custom_attributes'])
      timeline = build_incoming_timeline(payload)
      return if timeline.empty?

      cursor = attrs[CURSOR_KEY].to_i
      to_scan = select_messages_to_process(timeline, cursor)
      return if to_scan.empty?

      max_id = payload.map { |m| m['id'].to_i }.max
      changes = attrs.dup
      apply_first_contact_date!(changes, contact)

      to_scan.each do |msg|
        apply_message!(changes, msg)
      end

      changes[CURSOR_KEY] = max_id if max_id.positive?
      changes['loyalty_tier'] = Players::LoyaltyCalculator.tier(
        deposit_count: changes['deposit_count'].to_i,
        max_single_deposit: changes['max_single_deposit'].to_f
      )

      patch_if_changed(contact_id, attrs, changes)
    rescue StandardError => e
      Rails.logger.warn("[Players::ProfileService] sync failed conv=#{@conversation_id} #{e.class}: #{e.message}")
    end

    private

    def stringify_keys(hash)
      (hash || {}).stringify_keys
    end

    def apply_first_contact_date!(attrs, contact)
      return if attrs['first_contact_date'].present?

      ts = contact['created_at']
      attrs['first_contact_date'] = parse_time_iso(ts) if ts.present?
    end

    def select_messages_to_process(timeline, cursor)
      if cursor.positive?
        timeline.select { |m| m['id'].to_i > cursor }
      else
        timeline.last(BACKFILL_INCOMING_LIMIT)
      end
    end

    def build_incoming_timeline(payload)
      Array(payload)
        .select { |m| message_type_incoming?(m) }
        .reject { |m| m['content'].to_s.strip.empty? }
        .sort_by { |m| message_created_at_unix(m['created_at']) }
    end

    def message_type_incoming?(message)
      raw = message['message_type']
      case raw
      when 0, '0', 'incoming' then true
      else raw.to_i.zero?
      end
    end

    def message_created_at_unix(raw)
      case raw
      when Integer then raw
      when Numeric then raw.to_i
      when String
        s = raw.strip
        return s.to_i if s.match?(/\A\d{10,}\z/)

        Time.zone.parse(s).to_i
      else
        raw.to_i
      end
    rescue ArgumentError, TypeError
      0
    end

    def apply_message!(attrs, msg)
      body = msg['content'].to_s
      down = body.downcase
      msg_time = msg['created_at']

      detect_platform!(attrs, down)
      detect_payment_method!(attrs, down)
      detect_bonus_percent!(attrs, body)
      detect_cashout_intent!(attrs, down, msg_time)
      detect_cashout_completed!(attrs, down, body, msg_time)
      detect_deposit!(attrs, down, body, msg_time)
    end

    def detect_platform!(attrs, down)
      PLATFORM_ALIASES.each do |needle, slug|
        next unless down.include?(needle)

        attrs['preferred_platform'] = slug
        break
      end
    end

    def detect_payment_method!(attrs, down)
      PAYMENT_ALIASES.each do |pattern, slug|
        next unless down.match?(pattern)

        attrs['preferred_payment_method'] = slug
        break
      end
    end

    def detect_bonus_percent!(attrs, body)
      if (m = body.match(/(\d{1,2})\s*%/i)) && body.match?(/\b(?:bonus|promo|freeplay|free\s*play)\b/i)
        attrs['preferred_bonus_percentage'] = m[1].to_s
        return
      end
      return unless (m = body.match(/(\d{1,2})\s*(?:percent|%)\s*(?:bonus|promo)/i))

      attrs['preferred_bonus_percentage'] = m[1].to_s
    end

    def detect_cashout_intent!(attrs, down, msg_time)
      return unless down.match?(CASHOUT_INTENT)

      attrs['last_cashout_intent_date'] = parse_time_iso(msg_time)
    end

    def detect_cashout_completed!(attrs, down, body, msg_time)
      return unless down.match?(CASHOUT_DONE)

      amt = first_dollar_amount_in(body)
      if amt.positive?
        attrs['total_cashouts'] = attrs['total_cashouts'].to_f + amt
      end
      attrs['last_cashout_date'] = parse_time_iso(msg_time)
    end

    def detect_deposit!(attrs, down, body, msg_time)
      return unless down.match?(DEPOSIT_CONTEXT)

      amt = extract_deposit_amount(body, down)
      return unless amt.positive?

      attrs['last_deposit_amount'] = amt
      attrs['last_deposit_date'] = parse_time_iso(msg_time)
      attrs['deposit_count'] = attrs['deposit_count'].to_i + 1
      attrs['total_deposits'] = attrs['total_deposits'].to_f + amt
      prev_max = attrs['max_single_deposit'].to_f
      attrs['max_single_deposit'] = [prev_max, amt].max
    end

    def extract_deposit_amount(body, down)
      return 0.0 unless down.match?(DEPOSIT_CONTEXT)

      if (m = body.match(/\$\s*(\d+(?:\.\d{1,2})?)/))
        return m[1].to_f
      end

      if (m = body.match(/(\d+(?:\.\d{1,2})?)\s*(?:dollars|bucks)\b/i))
        return m[1].to_f
      end

      0.0
    end

    def first_dollar_amount_in(body)
      m = body.match(/\$\s*(\d+(?:\.\d{1,2})?)/)
      m ? m[1].to_f : 0.0
    end

    def parse_time_iso(raw)
      case raw
      when Integer, Numeric
        Time.zone.at(raw.to_i).iso8601
      when String
        Time.zone.parse(raw)&.iso8601
      else
        nil
      end
    end

    def patch_if_changed(contact_id, before, after)
      keys = (before.keys + after.keys).uniq
      meaningful = keys - [CURSOR_KEY]
      changed = meaningful.any? { |k| before[k] != after[k] }
      cursor_moved = before[CURSOR_KEY].to_i != after[CURSOR_KEY].to_i
      return unless changed || cursor_moved

      merge = before.merge(after)
      # Drop empty strings for optional fields we never want to wipe with blanks
      body = { custom_attributes: merge.compact }

      response = HTTParty.patch(
        "#{base_url}/api/v1/accounts/#{account_id}/contacts/#{contact_id}",
        headers: chatwoot_headers.merge('Content-Type' => 'application/json'),
        body: body.to_json,
        timeout: HTTP_TIMEOUT
      )

      if response.success?
        Rails.logger.info("[Players::ProfileService] updated contact=#{contact_id} conv=#{@conversation_id}")
      else
        Rails.logger.warn(
          "[Players::ProfileService] PATCH failed #{response.code} contact=#{contact_id}: #{response.body}"
        )
      end
    end

    def get_conversation
      res = HTTParty.get(
        "#{base_url}/api/v1/accounts/#{account_id}/conversations/#{@conversation_id}",
        headers: chatwoot_headers,
        timeout: HTTP_TIMEOUT
      )
      return nil unless res.success?

      res.parsed_response
    end

    def get_contact(contact_id)
      res = HTTParty.get(
        "#{base_url}/api/v1/accounts/#{account_id}/contacts/#{contact_id}",
        headers: chatwoot_headers,
        timeout: HTTP_TIMEOUT
      )
      return nil unless res.success?

      res.parsed_response['payload'] || res.parsed_response
    end

    def fetch_messages_payload
      res = HTTParty.get(
        "#{base_url}/api/v1/accounts/#{account_id}/conversations/#{@conversation_id}/messages",
        headers: chatwoot_headers,
        timeout: HTTP_TIMEOUT
      )
      return [] unless res.success?

      Array(res.parsed_response['payload'])
    end

    def chatwoot_headers
      { 'api_access_token' => chatwoot_token, 'Accept' => 'application/json' }
    end

    def chatwoot_token
      ENV.fetch('CHATWOOT_BRIDGE_API_TOKEN', '').to_s
    end

    def base_url
      @base_url ||= ENV.fetch('CHATWOOT_BRIDGE_BASE_URL', 'http://chatwoot.railway.internal:3000').to_s.chomp('/')
    end

    def account_id
      @account_id ||= begin
        aid = @bridge_account_id
        aid = aid.to_i if aid.present?
        if aid.present? && aid.positive?
          aid
        else
          ENV.fetch('CHATWOOT_BRIDGE_ACCOUNT_ID', '2').to_i
        end
      end
    end
  end
end
