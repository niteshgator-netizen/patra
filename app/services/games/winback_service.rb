# frozen_string_literal: true

# Feature 2 — Win-back. Finds dormant players (per their tier's dormancy threshold)
# and sends a DeepSeek-generated, Bella-voice re-engagement message via the normal
# Chatwoot outbound path. Idempotent across daily runs via winback_last_contacted_at.
module Games
  class WinbackService
    PERSONA_PROMPT = <<~'PROMPT'
      You are Bella, a cashier at an online sweepstakes gaming service, texting a player to win them back after they've gone quiet.
      Rules: never admit being an AI or a bot. No bullet points. No filler like "certainly" or "great to hear". Sound like a real human cashier texting on shift.
      Write 1-2 short lines only, casual and warm, nudging them to come back and play. Use the context provided. Do not include quotes around your message.
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

    # Returns true if a message was sent.
    def winback_contact(account, contact, pref)
      days = dormancy_days_for(contact, pref)
      return false if days <= 0

      last_active = last_activity_at(account, contact)
      return false if last_active.nil?                 # never engaged — no relationship to win back
      return false if last_active > days.days.ago      # still active

      # Anti-spam: skip anyone already contacted within their dormancy window.
      last_contacted = parse_time(custom_attr(contact, 'winback_last_contacted_at'))
      return false if last_contacted && last_contacted > days.days.ago

      conversation = account.conversations.where(contact_id: contact.id).order(updated_at: :desc).first
      return false unless conversation

      message = generate_message(contact, days)
      return false if message.blank?

      sent = send_outbound(account, conversation, message)
      return false unless sent

      stamp_contacted!(contact)
      Rails.logger.info("[Winback] SENT account=#{account.id} contact=#{contact.id} days_quiet=#{days} conv=#{conversation.id}")
      true
    end

    private

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

    def generate_message(contact, days)
      tier = contact.player_tier&.name.presence || 'regular'
      last_game = custom_attr(contact, 'preferred_platform').presence || 'your games'
      context = "Player tier: #{tier}. Last game: #{last_game}. Days quiet: #{days}. " \
                'Write a 1-2 line re-engagement text in Bella\'s voice.'
      Ai::DeepseekClient.complete(
        system_prompt: PERSONA_PROMPT,
        user_content: context,
        max_tokens: 120,
        temperature: 0.8
      )&.strip
    end

    def send_outbound(account, conversation, content)
      base_url = ENV.fetch('CHATWOOT_BRIDGE_BASE_URL', 'http://chatwoot.railway.internal:3000').to_s.chomp('/')
      token = ENV.fetch('CHATWOOT_BRIDGE_API_TOKEN', '').to_s
      account_id = account.id
      return false if token.blank?

      response = HTTParty.post(
        "#{base_url}/api/v1/accounts/#{account_id}/conversations/#{conversation.display_id}/messages",
        headers: { 'api_access_token' => token, 'Content-Type' => 'application/json' },
        body: { content: content, message_type: 'outgoing' }.to_json,
        timeout: 8
      )
      unless response.success?
        Rails.logger.error("[Winback] send HTTP #{response.code} conv=#{conversation.id}: #{response.body.to_s[0..200]}")
        return false
      end
      true
    rescue StandardError => e
      Rails.logger.error("[Winback] send failed conv=#{conversation&.id}: #{e.class}: #{e.message}")
      false
    end

    def stamp_contacted!(contact)
      attrs = (contact.custom_attributes || {}).merge('winback_last_contacted_at' => Time.current.iso8601)
      contact.update(custom_attributes: attrs)
    rescue StandardError => e
      Rails.logger.error("[Winback] stamp failed contact=#{contact&.id}: #{e.message}")
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
