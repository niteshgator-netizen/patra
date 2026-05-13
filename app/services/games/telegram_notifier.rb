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
    EVENT_API_ERROR = 'api_error'.freeze

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

      # Send raw text (used by Test Connection with explicit credentials)
      def send_raw(bot_token:, chat_id:, text:)
        send_message(bot_token, chat_id, text)
      end

      private

      def notify(account:, event:, text:, ignore_filters: false)
        channel = resolve_channel(account, event, ignore_filters: ignore_filters)
        return { ok: false, reason: 'no channel configured' } unless channel

        result = send_message(channel[:bot_token], channel[:chat_id], text)
        record_outcome(channel[:record], result)
        result
      rescue StandardError => e
        Rails.logger.error("[TelegramNotifier] #{e.class}: #{e.message}")
        { ok: false, error: e.message }
      end

      # Returns hash with :bot_token, :chat_id, :record (or nil if global ENV)
      def resolve_channel(account, event, ignore_filters: false)
        # 1. Try per-account NotificationChannel
        if account && defined?(NotificationChannel)
          nc = account.notification_channels.active.find_by(channel_type: 'telegram')
          if nc && nc.configured? && (ignore_filters || event.nil? || nc.should_notify?(event))
            creds = nc.credentials || {}
            return { bot_token: creds['bot_token'], chat_id: creds['chat_id'], record: nc }
          end
        end

        # 2. Fall back to global ENV
        token = ENV['TELEGRAM_BOT_TOKEN'].presence
        chat_id = ENV['TELEGRAM_CHAT_ID'].presence
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
    end
  end
end
