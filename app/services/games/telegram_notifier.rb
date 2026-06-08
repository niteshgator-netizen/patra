# Sends notifications to Telegram via bot API.
# Resolution order:
#   1. Per-account NotificationChannel (if configured + active)
#   2. Global ENV TELEGRAM_BOT_TOKEN + TELEGRAM_CHAT_ID
#   3. Silent no-op
#
# Usage:
#   Games::TelegramNotifier.cashout_alert(cashout_request)
#   Games::TelegramNotifier.load_alert(game_action)
#   Games::TelegramNotifier.load_failed(game_action)
#   Games::TelegramNotifier.cashout_failed(game_action, cashout_request)
#   Games::TelegramNotifier.human_escalation(account:, contact:, reason:, conversation: nil)
#   Games::TelegramNotifier.payment_pending_alert(contact:, payment_details:)
#   Games::TelegramNotifier.api_error(account:, message:, details: nil)
#   Games::TelegramNotifier.test_message(account:, custom_text: nil)

require 'net/http'
require 'uri'
require 'json'

module Games
  class TelegramNotifier
    EVENT_LOAD_SUCCESS = 'load_success'.freeze
    EVENT_LOAD_FAILED = 'load_failed'.freeze
    EVENT_CASHOUT_REQUEST = 'cashout_request'.freeze
    EVENT_CASHOUT_FAILED = 'cashout_failed'.freeze
    EVENT_HUMAN_ESCALATION = 'human_escalation'.freeze
    EVENT_PAYMENT_PENDING = 'payment_pending'.freeze
    EVENT_SECRET_PHRASE = 'secret_phrase'.freeze
    EVENT_API_ERROR = 'api_error'.freeze
    EVENT_LOW_BALANCE = 'low_balance'.freeze
    EVENT_WINBACK_MANUAL = 'winback_manual'.freeze

    class << self
      def cashout_alert(cashout_request)
        notify(
          account: cashout_request.account,
          event: EVENT_CASHOUT_REQUEST,
          text: build_cashout_text(cashout_request)
        )
      end

      def load_alert(game_action)
        notify(
          account: game_action.account,
          event: EVENT_LOAD_SUCCESS,
          text: build_load_text(game_action)
        )
      end

      def load_failed(game_action)
        notify(
          account: game_action.account,
          event: EVENT_LOAD_FAILED,
          text: build_load_failed_text(game_action)
        )
      end

      def cashout_failed(game_action, cashout_request = nil)
        notify(
          account: game_action.account,
          event: EVENT_CASHOUT_FAILED,
          text: build_cashout_failed_text(game_action, cashout_request)
        )
      end

      def human_escalation(account:, contact:, reason:, conversation: nil)
        notify(
          account: account,
          event: EVENT_HUMAN_ESCALATION,
          text: build_escalation_text(contact, reason, conversation)
        )
      end

      def payment_pending_alert(contact:, payment_details:)
        details = payment_details.stringify_keys
        txn_id = details['transaction_id'].to_s.strip
        return { ok: false, reason: 'deduped' } if txn_id.present? && payment_pending_alert_sent?(txn_id)

        account = contact.account
        notify(
          account: account,
          event: EVENT_PAYMENT_PENDING,
          text: build_payment_pending_text(contact, details)
        )
      rescue StandardError => e
        Rails.logger.error("[TelegramNotifier] payment_pending_alert #{e.class}: #{e.message}")
        { ok: false, error: e.message }
      end

      def secret_phrase_triggered(account:, conversation:, phrase_record:)
        notify(
          account: account,
          event: EVENT_SECRET_PHRASE,
          text: build_secret_phrase_text(conversation, phrase_record)
        )
      end

      def api_error(account:, message:, details: nil)
        notify(
          account: account,
          event: EVENT_API_ERROR,
          text: build_api_error_text(message, details)
        )
      end

      def test_message(account:, custom_text: nil)
        text = custom_text || "🎯 *Test from Patra*\n\nIf you see this, your Telegram notifications are working\\."
        notify(account: account, event: nil, text: text, ignore_filters: true)
      end

      def low_balance_alert(game_name:, balance:, threshold:, account:)
        msg = "⚠️ Low balance on #{game_name}\n" \
              "Balance: $#{'%.2f' % balance}\n" \
              "Threshold: $#{threshold}\n" \
              "Top up soon!"
        notify(account: account, event: EVENT_LOW_BALANCE, text: msg, plain: true)
      end

      # Win-back manual-send alert. Routed through notify() so it fans out to every
      # group that enables 'winback_manual' (zero channels -> global ENV fallback).
      # plain: true keeps the AI message + URL from being mangled by MarkdownV2.
      def winback_manual_alert(account:, player:, days_dormant:, tier:, diagnosis:, message:, profile_url: nil)
        lines = []
        lines << '🔄 WIN-BACK (manual send needed)'
        lines << "Player: #{player} | Tier: #{tier} | Quiet: #{days_dormant}d"
        lines << "Why: #{diagnosis}"
        lines << 'Suggested message:'
        lines << "\"#{message}\""
        lines << profile_url.to_s if profile_url.present?
        notify(account: account, event: EVENT_WINBACK_MANUAL, text: lines.join("\n"), plain: true)
      end

      def send_to_cashout_group(text, account: nil)
        token = ENV['TELEGRAM_BOT_TOKEN'].presence
        chat_id = ENV['TELEGRAM_CASHOUT_GROUP_ID'].presence || ENV['TELEGRAM_CHAT_ID'].presence
        return { ok: false, reason: 'no telegram configured' } if token.blank? || chat_id.blank?

        send_message_plain(token, chat_id, text)
      end

      # Send raw text (used by Test Connection with explicit credentials)
      def send_raw(bot_token:, chat_id:, text:)
        send_message(bot_token, chat_id, text)
      end

      private

      def notify(account:, event:, text:, ignore_filters: false, plain: false)
        Rails.logger.info("[TelegramNotifier] event=#{event} account_id=#{account&.id} text_chars=#{text.to_s.length}")

        channels = resolve_channels(account, event, ignore_filters: ignore_filters)

        # FANOUT: per-account channels matched — send to EVERY matching group.
        if channels.present?
          any_ok = false
          channels.each do |channel|
            result = send_one(channel[:bot_token], channel[:chat_id], text, plain: plain)
            Rails.logger.info("[TelegramNotifier] sent per-account chat_id=#{channel[:chat_id]} ok=#{result[:ok]}")
            record_outcome(channel[:record], result)
            any_ok ||= result[:ok]
          rescue StandardError => e
            # Per-channel failure must not stop the other channels.
            Rails.logger.error("[TelegramNotifier] channel send failed chat_id=#{channel[:chat_id]} #{e.class}: #{e.message}")
          end
          return { ok: any_ok, channels: channels.size }
        end

        # No channel matched. If channels EXIST but none enabled this event, respect
        # the filters and send nothing. Only when there are ZERO configured channels
        # do we fall back to the global ENV group (UNCHANGED from before).
        if any_configured_channel?(account)
          Rails.logger.info("[TelegramNotifier] event=#{event} suppressed — channels configured but none enabled it")
          return { ok: true, channels: 0, suppressed: true }
        end

        env = env_channel
        unless env
          Rails.logger.warn("[TelegramNotifier] no channel resolved for event=#{event} account=#{account&.id}")
          return { ok: false, reason: 'no channel configured' }
        end

        result = send_one(env[:bot_token], env[:chat_id], text, plain: plain)
        Rails.logger.info("[TelegramNotifier] sent global-env chat_id=#{env[:chat_id]} ok=#{result[:ok]}")
        result
      rescue StandardError => e
        Rails.logger.error("[TelegramNotifier] #{e.class}: #{e.message}")
        { ok: false, error: e.message }
      end

      def send_one(bot_token, chat_id, text, plain: false)
        plain ? send_message_plain(bot_token, chat_id, text) : send_message(bot_token, chat_id, text)
      end

      # ARRAY of { bot_token, chat_id, record } for EVERY per-account active+configured
      # channel whose should_notify?(event) is true (all configured when event is nil
      # or ignore_filters). Empty when none match / none configured.
      def resolve_channels(account, event, ignore_filters: false)
        channels = configured_channels(account)
        channels = channels.select { |nc| nc.should_notify?(event) } unless ignore_filters || event.nil?
        channels.map { |nc| channel_hash(nc) }
      end

      def configured_channels(account)
        return [] unless account && defined?(NotificationChannel)
        account.notification_channels.active.select(&:configured?)
      rescue StandardError => e
        Rails.logger.error("[TelegramNotifier] channel lookup failed account=#{account&.id}: #{e.message}")
        []
      end

      def any_configured_channel?(account)
        configured_channels(account).present?
      end

      def channel_hash(nc)
        creds = nc.credentials || {}
        { bot_token: creds['bot_token'], chat_id: creds['chat_id'], record: nc }
      end

      # Global ENV group — the no-channel fallback. Keeps the cashout-group id as a
      # secondary so low_balance/winback (which used it) still resolve if
      # TELEGRAM_CHAT_ID is unset.
      def env_channel
        token = ENV['TELEGRAM_BOT_TOKEN'].presence
        chat_id = ENV['TELEGRAM_CHAT_ID'].presence || ENV['TELEGRAM_CASHOUT_GROUP_ID'].presence
        return nil if token.blank? || chat_id.blank?

        { bot_token: token, chat_id: chat_id, record: nil }
      end

      def record_outcome(record, result)
        return unless record

        if result[:ok]
          record.record_success!
        else
          record.record_failure!
        end
      end

      def build_cashout_text(cr)
        contact_name = cr.contact&.name || 'Unknown'
        deposit_line = cr.original_deposit ? "$#{cr.original_deposit} via #{cr.deposit_payment_method || 'unknown'}" : 'N/A'
        rules_list = (cr.applied_rules || []).map { |r| "• #{r}" }.join("\n")

        lines = []
        lines << "💸 *Cashout Request — $#{cr.cashout_amount}*"
        lines << ""
        lines << "*Player:* #{esc(contact_name)}"
        lines << "*Game username:* `#{esc(cr.game_username)}`"
        lines << "*Original deposit:* #{esc(deposit_line)}"
        lines << "*Total points:* $#{esc((cr.total_points || 'N/A').to_s)}"
        lines << "*Cashout:* *$#{esc(cr.cashout_amount.to_s)}*"
        lines << "*Remaining in game:* $#{esc(cr.remaining_points.to_s)}"
        lines << ""
        lines << "*Tip:* $#{esc(cr.tip_amount.to_s)}" if cr.tip_amount.to_f > 0
        lines << "*Reload back to game:* $#{esc(cr.reload_amount.to_s)}" if cr.reload_amount.to_f > 0
        lines << ""
        if cr.cashout_payment_method.present? || cr.cashout_destination_handle.present?
          lines << "*Pay to:* #{esc(cr.cashout_payment_method || 'TBD')} #{esc(cr.cashout_destination_handle || '')}"
        else
          lines << "*Pay to:* TBD \\(waiting for customer\\)"
        end
        if rules_list.present?
          lines << ""
          lines << "*Applied rules:*"
          lines << esc(rules_list)
        end
        lines << ""
        lines << "_Patra · Request ID: #{cr.id}_"
        lines.join("\n")
      end

      def build_load_text(action)
        lines = []
        lines << "✅ *Load executed — $#{esc(action.amount.to_s)}*"
        lines << ""
        lines << "*Game username:* `#{esc(action.game_username)}`"
        lines << "*Amount:* $#{esc(action.amount.to_s)}"
        lines << "*Method:* #{esc(action.payment_method || 'N/A')}"
        lines << ""
        lines << "_Patra · Action ID: #{action.id}_"
        lines.join("\n")
      end

      def build_load_failed_text(action)
        lines = []
        lines << "❌ *Load FAILED — $#{esc(action.amount.to_s)}*"
        lines << ""
        lines << "*Game username:* `#{esc(action.game_username)}`"
        lines << "*Amount:* $#{esc(action.amount.to_s)}"
        lines << "*Error:* #{esc(action.api_response_message || 'unknown error')}"
        lines << "*Code:* #{esc(action.api_response_code.to_s)}" if action.api_response_code
        lines << ""
        lines << "⚠️ *Needs human action* — verify the player got their load\\."
        lines << ""
        lines << "_Patra · Action ID: #{action.id}_"
        lines.join("\n")
      end

      def build_cashout_failed_text(action, cashout_request)
        lines = []
        lines << "❌ *Cashout FAILED — $#{esc(action.amount.to_s)}*"
        lines << ""
        lines << "*Player:* #{esc(cashout_request&.contact&.name || 'Unknown')}"
        lines << "*Game username:* `#{esc(action.game_username)}`"
        lines << "*Amount:* $#{esc(action.amount.to_s)}"
        lines << "*Error:* #{esc(action.api_response_message || 'unknown error')}"
        lines << ""
        lines << "⚠️ *Needs human action* — withdraw manually before paying\\."
        lines << ""
        lines << "_Patra · Action ID: #{action.id}_"
        lines.join("\n")
      end

      def build_secret_phrase_text(conversation, phrase_record)
        contact_name = conversation.contact&.name.to_s.presence || 'Unknown contact'
        action_label = if phrase_record.action == 'pause_ai_and_notify'
                         'AI PAUSED for this conversation'
                       else
                         'AI continues normally'
                       end

        lines = []
        lines << '🔐 *Secret phrase triggered*'
        lines << ''
        lines << "*Contact:* #{esc(contact_name)}"
        lines << "*Conversation:* \\##{esc(conversation.display_id.to_s)}"
        lines << "*Action:* #{esc(action_label)}"
        lines << "*Total triggers:* #{phrase_record.trigger_count}"
        lines.join("\n")
      end

      def build_escalation_text(contact, reason, conversation)
        lines = []
        lines << "🚨 *Human escalation needed*"
        lines << ""
        lines << "*Player:* #{esc(contact&.name || 'Unknown')}"
        lines << "*Reason:* #{esc(reason)}"
        if conversation
          lines << "*Conversation:* \\##{esc(conversation.display_id.to_s)}"
        end
        lines.join("\n")
      end

      def build_payment_pending_text(contact, details)
        account_id = contact.account_id
        contact_url = "https://patrahq.com/app/accounts/#{account_id}/contacts/#{contact.id}"
        lines = []
        lines << "⏳ *Payment pending verification*"
        lines << ""
        lines << "*Player:* #{esc(contact.name || 'Unknown')}"
        lines << "*Link:* #{esc(contact_url)}"
        lines << "*Amount:* $#{esc(format('%.2f', details['amount'].to_f))}"
        lines << "*Platform:* #{esc(details['platform'].to_s)}"
        lines << "*Sender:* #{esc(details['sender_name'].to_s.presence || 'N/A')}"
        lines << "*Recipient:* #{esc(details['recipient_handle'].to_s.presence || 'N/A')}"
        lines << "*Txn ID:* `#{esc(details['transaction_id'].to_s.presence || 'N/A')}`"
        lines << "*Status:* #{esc(details['raw_status'].to_s.presence || 'N/A')}"
        lines << ""
        lines << "_Patra · awaiting IMAP confirmation_"
        lines.join("\n")
      end

      def payment_pending_alert_sent?(txn_id)
        redis = Redis.new(Redis::Config.app)
        key = "telegram:payment_pending:#{txn_id}"
        return true if redis.get(key).present?

        redis.setex(key, 1.hour.to_i, '1')
        false
      rescue StandardError => e
        Rails.logger.warn("[TelegramNotifier] payment_pending dedupe skipped: #{e.message}")
        false
      end

      def build_api_error_text(message, details)
        lines = []
        lines << "⚠️ *API error*"
        lines << ""
        lines << "*Message:* #{esc(message)}"
        lines << "*Details:* #{esc(details.to_s)}" if details.present?
        lines.join("\n")
      end

      # Telegram MarkdownV2 requires escaping these chars
      def esc(text)
        return '' if text.nil?

        text.to_s.gsub(/([_\*\[\]\(\)~`>#\+\-=\|\{\}\.!])/) { |m| "\\#{m}" }
      end

      def send_message(bot_token, chat_id, text)
        uri = URI("https://api.telegram.org/bot#{bot_token}/sendMessage")
        http = Net::HTTP.new(uri.host, uri.port)
        http.use_ssl = true
        http.read_timeout = 5
        http.open_timeout = 5

        req = Net::HTTP::Post.new(uri.request_uri, 'Content-Type' => 'application/json')
        req.body = {
          chat_id: chat_id,
          text: text,
          parse_mode: 'MarkdownV2',
          disable_web_page_preview: true
        }.to_json

        response = http.request(req)
        if response.is_a?(Net::HTTPSuccess)
          { ok: true, status: response.code }
        else
          body_preview = response.body.to_s[0..300]
          Rails.logger.error("[Telegram] non-2xx response: #{response.code} body=#{body_preview}")
          { ok: false, status: response.code, body: body_preview }
        end
      rescue StandardError => e
        Rails.logger.error("[Telegram] send failed: #{e.message}")
        { ok: false, error: e.message }
      end

      def send_message_plain(bot_token, chat_id, text)
        uri = URI("https://api.telegram.org/bot#{bot_token}/sendMessage")
        http = Net::HTTP.new(uri.host, uri.port)
        http.use_ssl = true
        http.read_timeout = 5
        http.open_timeout = 5

        req = Net::HTTP::Post.new(uri.request_uri, 'Content-Type' => 'application/json')
        req.body = {
          chat_id: chat_id,
          text: text,
          disable_web_page_preview: true
        }.to_json

        response = http.request(req)
        if response.is_a?(Net::HTTPSuccess)
          { ok: true, status: response.code }
        else
          body_preview = response.body.to_s[0..300]
          Rails.logger.error("[Telegram] non-2xx response: #{response.code} body=#{body_preview}")
          { ok: false, status: response.code, body: body_preview }
        end
      rescue StandardError => e
        Rails.logger.error("[Telegram] send failed: #{e.message}")
        { ok: false, error: e.message }
      end
    end
  end
end
