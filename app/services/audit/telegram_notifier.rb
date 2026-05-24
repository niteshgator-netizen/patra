# frozen_string_literal: true

require 'net/http'
require 'uri'
require 'json'

module Audit
  class TelegramNotifier
    class << self
      def message_edited(message:, old_content:, editor_name:)
        notify(
          "⚠️ #{editor_name} edited a message in conversation ##{message.conversation_id}\n" \
          "Original: #{truncate(old_content)}\n" \
          "New: #{truncate(message.content)}\n" \
          "Time: #{Time.current.strftime('%Y-%m-%d %H:%M %Z')}"
        )
      end

      def message_deleted(message:, deleted_content:, deleter_name:)
        notify(
          "⚠️ #{deleter_name} deleted a message in conversation ##{message.conversation_id}\n" \
          "Original: #{truncate(deleted_content)}\n" \
          "New: DELETED\n" \
          "Time: #{Time.current.strftime('%Y-%m-%d %H:%M %Z')}"
        )
      end

      def deception_flag(account:, text:)
        notify(text, account: account)
      end

      def approval_needed(account:, text:)
        notify(text, account: account)
      end

      def sla_violation(account:, text:)
        notify(text, account: account)
      end

      private

      def notify(text, account: nil)
        safe_telegram do
          chat_id = ENV['TELEGRAM_CHAT_ID']
          token = resolve_token(account)
          return if chat_id.blank? || token.blank?

          uri = URI("https://api.telegram.org/bot#{token}/sendMessage")
          Net::HTTP.post_form(uri, 'chat_id' => chat_id, 'text' => text)
        end
      end

      def resolve_token(account)
        return ENV['TELEGRAM_BOT_TOKEN'] if account.blank?

        channel = account.notification_channels&.find_by(channel_type: 'telegram', active: true)
        channel&.credentials&.dig('bot_token') || ENV['TELEGRAM_BOT_TOKEN']
      end

      def truncate(text, max: 500)
        str = text.to_s
        str.length > max ? "#{str[0, max]}…" : str
      end

      def safe_telegram
        yield
      rescue StandardError => e
        Rails.logger.error("[Audit::TelegramNotifier] #{e.class}: #{e.message}")
      end
    end
  end
end
