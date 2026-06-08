# frozen_string_literal: true

# Win-back 2.0 — finds dormant players, has DeepSeek diagnose WHY each one went
# quiet and write a per-player re-engagement message, then delivers it:
#   * <= 7 days quiet  -> creates a NORMAL outgoing message flagged winback:true.
#                         It shows in the inbox naturally and flows through Patra's
#                         normal send pipe (message_created webhook -> FbReplyJob ->
#                         SendApiService -> OutboundDispatcher -> Zernio), where the
#                         winback flag makes SendApiService attach the HUMAN_AGENT
#                         tag (the only tag that reaches the 24h-7day window).
#   * > 7 days quiet   -> no FB tag can reach them, so go straight to the Telegram
#                         manual-send fallback (+ an internal note on the thread).
# Every send also labels the conversation 'follow-up' for a future inbox filter.
# Idempotent across daily runs via winback_last_contacted_at.
module Games
  class WinbackService
    FB_TAG_MAX_DAYS = 7
    FOLLOW_UP_LABEL = 'follow-up'

    PERSONA_PROMPT = <<~'PROMPT'
      You are Bella, a cashier at an online sweepstakes gaming service. A player has gone quiet and you want to win them back.
      Read the player context and diagnose WHY this specific player likely went quiet — upset, an unresolved issue, a big win then left, hit failed transactions, or just drifted. Then write the single best message to re-engage THEM specifically: restart the conversation, rebuild the relationship, get them back playing, and where it fits naturally, surface referral value.
      Voice: a real human cashier texting on shift. Never admit being an AI or a bot. Max 2 short lines. No bullet points. No filler like "certainly" or "great to hear". This must be per-player, never a generic template.
      Respond with ONLY compact JSON, no markdown: {"diagnosis":"<one short line on why they left>","message":"<the message to send the player>"}
    PROMPT

    def self.run_all
      new.run_all
    end

    def run_all
      ReplyPreference.where(winback_enabled: true).find_each do |pref|
        account = pref.account
        next unless account

        run_for_account(account, pref)
      rescue StandardError => e
        Rails.logger.error("[Winback] account #{pref&.account_id} failed: #{e.class}: #{e.message}")
      end
    rescue StandardError => e
      # winback_enabled column may not exist before the migration deploys — fail safe.
      Rails.logger.warn("[Winback] run_all skipped: #{e.class}: #{e.message}")
    end

    def run_for_account(account, pref)
      sent = 0
      account.contacts.find_each do |contact|
        sent += 1 if winback_contact(account, contact, pref)
      rescue StandardError => e
        Rails.logger.error("[Winback] contact #{contact&.id} failed: #{e.class}: #{e.message}")
      end
      Rails.logger.info("[Winback] account=#{account.id} sent=#{sent}")
      sent
    end

    # Returns true only if a message was actually delivered (FB pipe or Telegram).
    def winback_contact(account, contact, pref)
      days = dormancy_days_for(contact, pref)
      return false if days <= 0

      last_active = last_activity_at(account, contact)
      return false if last_active.nil?                 # never engaged — no relationship to win back
      return false if last_active > days.days.ago      # still active

      # Anti-spam / idempotency: skip anyone already contacted within their window.
      last_contacted = parse_time(custom_attr(contact, 'winback_last_contacted_at'))
      return false if last_contacted && last_contacted > days.days.ago

      conversation = account.conversations.where(contact_id: contact.id).order(updated_at: :desc).first
      return false unless conversation

      days_dormant = ((Time.current - last_active) / 1.day).floor
      context = build_player_context(account, contact, conversation, days_dormant)
      ai = generate_message(context)
      message = ai[:message]
      return false if message.blank?

      diagnosis = ai[:diagnosis].presence || diagnose_fallback(context)

      path =
        if days_dormant <= FB_TAG_MAX_DAYS
          deliver_via_normal_pipe(account, conversation, message)
        else
          # > 7 days: no FB tag can reach them — human sends from the real page.
          deliver_via_telegram(account, contact, conversation, message, context, diagnosis, days_dormant)
        end

      return false unless path

      label_followup(conversation)      # mark AI-outreach conversations for a future filter
      stamp_contacted!(contact)
      Rails.logger.info("[Winback] SENT account=#{account.id} contact=#{contact.id} days=#{days_dormant} path=#{path}")
      true
    end

    private

    # ---------- delivery ----------

    # <= 7 days: create a NORMAL flagged outgoing message. Patra's normal pipe sends
    # it (with the HUMAN_AGENT tag, applied by SendApiService when winback:true) and
    # it shows in the inbox. Returns 'fb' on create, false on failure.
    def deliver_via_normal_pipe(account, conversation, text)
      conversation.messages.create!(
        account: account,
        inbox: conversation.inbox,
        content: text,
        message_type: :outgoing,
        additional_attributes: { 'winback' => true }
      )
      'fb'
    rescue StandardError => e
      Rails.logger.warn("[Winback] winback message create failed conv=#{conversation&.id}: #{e.class}: #{e.message}")
      false
    end

    # > 7 days: Telegram manual-send fallback (+ an internal note on the thread so a
    # human can see what to send). Returns 'telegram' on success, false otherwise.
    def deliver_via_telegram(account, contact, conversation, message, context, diagnosis, days_dormant)
      result = safe_telegram do
        Games::TelegramNotifier.winback_manual_alert(
          account: account,
          player: context[:player],
          days_dormant: days_dormant,
          tier: context[:tier],
          diagnosis: diagnosis,
          message: message,
          profile_url: context[:profile_url]
        )
      end
      ok = result.is_a?(Hash) ? (result[:ok] != false) : result.present?
      return false unless ok

      add_private_note(account, conversation, "🔄 Win-back (manual send — player >#{FB_TAG_MAX_DAYS}d quiet): #{message}")
      'telegram'
    end

    # Private note: the fb_reply webhook ignores private messages, so this never
    # triggers an FB send — it's purely an internal record of what to send manually.
    def add_private_note(account, conversation, text)
      conversation.messages.create!(
        account: account,
        inbox: conversation.inbox,
        content: text,
        message_type: :outgoing,
        private: true
      )
    rescue StandardError => e
      Rails.logger.warn("[Winback] private note create failed conv=#{conversation&.id}: #{e.message}")
    end

    # Idempotent: add_labels does a union, and we also short-circuit if present.
    def label_followup(conversation)
      labels = Array(conversation.label_list)
      return if labels.include?(FOLLOW_UP_LABEL)

      conversation.add_labels([FOLLOW_UP_LABEL])
    rescue StandardError => e
      Rails.logger.warn("[Winback] follow-up label failed conv=#{conversation&.id}: #{e.message}")
    end

    # ---------- AI generation ----------

    def generate_message(context)
      raw = Ai::DeepseekClient.complete(
        system_prompt: PERSONA_PROMPT,
        user_content: build_prompt(context),
        max_tokens: 320,
        temperature: 0.8
      )
      parse_ai_output(raw)
    end

    def build_prompt(context)
      <<~TXT
        Player: #{context[:player]}
        Tier: #{context[:tier]}
        Activity score: #{context[:activity_score].presence || 'n/a'}
        Lifecycle stage: #{context[:lifecycle_stage].presence || 'n/a'}
        Preferred game/platform: #{context[:preferred_platform]}
        Days quiet: #{context[:days_dormant]}
        Loads: #{context[:total_loads]} totaling $#{context[:total_loaded]}
        Cashouts: #{context[:total_cashouts]} totaling $#{context[:total_cashed_out]}
        Recent failed transactions (60d): #{context[:recent_failures]}
        Last activity type: #{context[:last_action_type]}
        Recent conversation (oldest first):
        #{context[:history]}
      TXT
    end

    # DeepseekClient already does reasoning_content -> content. Parse the JSON;
    # if it isn't clean JSON, treat the whole reply as the message (diagnosis nil).
    def parse_ai_output(raw)
      return { message: nil, diagnosis: nil } if raw.blank?

      json = raw.to_s.sub(/\A```(?:json)?\s*/i, '').sub(/\s*```\z/, '').strip
      if (brace = json.match(/\{.*\}/m))
        begin
          data = JSON.parse(brace[0])
          msg = data['message'].to_s.strip
          return { message: msg.presence, diagnosis: data['diagnosis'].to_s.strip.presence } if msg.present?
        rescue JSON::ParserError
          # fall through to raw-as-message
        end
      end
      { message: raw.to_s.strip, diagnosis: nil }
    end

    # ---------- per-player context ----------

    def build_player_context(account, contact, conversation, days_dormant)
      attrs = contact.custom_attributes || {}
      base = GameAction.where(account_id: account.id, contact_id: contact.id)
      loads = base.where(action_type: 'load', status: 'success')
      cashouts = base.where(action_type: 'cashout', status: 'success')
      failures = base.where(status: 'failed').where('created_at >= ?', 60.days.ago).count
      last_action = base.order(created_at: :desc).first

      {
        player: player_label(contact),
        tier: (contact.player_tier&.name.presence || attrs['loyalty_tier'].presence || 'regular'),
        activity_score: attrs['activity_score'],
        lifecycle_stage: attrs['lifecycle_stage'],
        preferred_platform: attrs['preferred_platform'].presence || 'unknown',
        days_dormant: days_dormant,
        total_loads: loads.count,
        total_loaded: loads.sum(:amount).to_f.round(2),
        total_cashouts: cashouts.count,
        total_cashed_out: cashouts.sum(:amount).to_f.round(2),
        recent_failures: failures,
        last_action_type: last_action&.action_type || 'none',
        history: recent_history(conversation),
        profile_url: conversation_profile_url(conversation)
      }
    end

    def recent_history(conversation, limit = 10)
      msgs = conversation.messages
                         .where(message_type: %i[incoming outgoing])
                         .order(created_at: :desc)
                         .limit(limit)
                         .to_a
                         .reverse
      lines = msgs.filter_map do |m|
        text = m.content.to_s.strip
        next if text.blank?
        who = m.message_type.to_s == 'incoming' ? 'player' : 'cashier'
        "#{who}: #{text[0, 200]}"
      end
      lines.present? ? lines.join("\n") : '(no prior messages)'
    rescue StandardError => e
      Rails.logger.warn("[Winback] history build failed conv=#{conversation&.id}: #{e.message}")
      '(history unavailable)'
    end

    def conversation_profile_url(conversation)
      aa = conversation.additional_attributes || {}
      ca = (conversation.contact&.custom_attributes || {})
      aa['profile_url'].presence ||
        aa['conversation_url'].presence ||
        ca['profile_url'].presence
    rescue StandardError
      nil
    end

    def player_label(contact)
      contact.name.presence ||
        contact.try(:identifier).presence ||
        contact.try(:email).presence ||
        "contact ##{contact.id}"
    end

    # Heuristic one-liner used only when the AI didn't return a diagnosis.
    def diagnose_fallback(context)
      return 'hit failed transactions — may be frustrated' if context[:recent_failures].to_i.positive?
      return 'cashed out and drifted away' if context[:total_cashouts].to_i.positive? && context[:days_dormant].to_i > FB_TAG_MAX_DAYS
      return 'used to deposit, then went quiet' if context[:total_loads].to_i.positive?

      'low-activity player who drifted off'
    end

    # ---------- dormancy ----------

    def dormancy_days_for(contact, pref)
      tier = contact.player_tier&.name.to_s
      case tier
      when 'vip'
        pref_int(pref, :winback_dormant_days_vip, 3)
      when 'new_player'
        pref_int(pref, :winback_dormant_days_new, 7)
      else
        pref_int(pref, :winback_dormant_days_regular, 14)
      end
    end

    def last_activity_at(account, contact)
      conv_ids = account.conversations.where(contact_id: contact.id).select(:id)
      last_inbound = Message.where(conversation_id: conv_ids, message_type: :incoming).maximum(:created_at)
      last_action  = GameAction.where(account_id: account.id, contact_id: contact.id).maximum(:created_at)
      [last_inbound, last_action].compact.max
    end

    # ---------- helpers ----------

    def stamp_contacted!(contact)
      attrs = (contact.custom_attributes || {}).merge('winback_last_contacted_at' => Time.current.iso8601)
      contact.update(custom_attributes: attrs)
    rescue StandardError => e
      Rails.logger.error("[Winback] stamp failed contact=#{contact&.id}: #{e.message}")
    end

    def safe_telegram
      yield
    rescue StandardError => e
      Rails.logger.error("[Winback] Telegram call failed: #{e.class}: #{e.message}")
      nil
    end

    def custom_attr(contact, key)
      (contact.custom_attributes || {})[key]
    end

    def parse_time(str)
      return nil if str.blank?
      Time.parse(str.to_s)
    rescue ArgumentError
      nil
    end

    # Safe integer read for columns that may not exist until the migration deploys.
    def pref_int(pref, name, default)
      return default unless pref.respond_to?(name)
      val = pref.public_send(name)
      val.nil? ? default : val.to_i
    rescue StandardError
      default
    end
  end
end
