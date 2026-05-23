# frozen_string_literal: true

# Notifies the account owner via Telegram when an agent (or Bella) edits or
# deletes a sent message. The notifier is the publisher half only — the
# subscriber (trigger / hook) is deferred to a follow-up bucket so we can wire
# it in once we've decided exactly which model callback or service entry
# point should detect agent edits/deletes (Decision #9 in the Phase H
# triage).
#
# Resolution is intentionally self-contained: uses the same global ENV vars
# (TELEGRAM_BOT_TOKEN + TELEGRAM_CASHOUT_GROUP_ID) that Games::TelegramNotifier
# already falls back to. No new env vars required if those are configured.
#
# HTTParty everywhere (matches Messaging::ZernioProvider, Zernio::OauthService,
# Zernio::HistorySyncService).
module Zernio
  class AgentActionNotifier
    TELEGRAM_API_BASE = 'https://api.telegram.org'
    HTTP_TIMEOUT = 5
    TEXT_TRUNCATION_LIMIT = 200

    class << self
      # Called when an outgoing message's content changes after delivery.
      # Records the before/after content for audit; the actor is whoever
      # made the edit (defaults to 'Bella' when unspecified — the AI is the
      # most common editor today, but the trigger bucket will pass the real
      # User name when available).
      def notify_edit(message:, old_content:, new_content:, editor_name: 'Bella')
        return :no_token if bot_token.blank?

        text = [
          '✏️ *Message Edited*',
          "Editor: #{escape_markdown(editor_name)}",
          "Inbox: #{escape_markdown(message&.inbox&.name || 'Unknown')}",
          "Conversation: \\##{message&.conversation_id}",
          '',
          "OLD: #{truncate_for_telegram(old_content)}",
          "NEW: #{truncate_for_telegram(new_content)}",
          '',
          "Time: #{Time.current.strftime('%Y-%m-%d %H:%M UTC')}"
        ].join("\n")

        deliver(text)
      end

      # Called when an outgoing message is deleted (by agent or Bella).
      def notify_delete(message:, deleted_content:, deleter_name: 'Bella')
        return :no_token if bot_token.blank?

        text = [
          '🗑️ *Message Deleted*',
          "Deleted by: #{escape_markdown(deleter_name)}",
          "Inbox: #{escape_markdown(message&.inbox&.name || 'Unknown')}",
          "Conversation: \\##{message&.conversation_id}",
          '',
          "DELETED: #{truncate_for_telegram(deleted_content)}",
          '',
          "Time: #{Time.current.strftime('%Y-%m-%d %H:%M UTC')}"
        ].join("\n")

        deliver(text)
      end

      private

      def deliver(text)
        response = HTTParty.post(
          "#{TELEGRAM_API_BASE}/bot#{bot_token}/sendMessage",
          headers: { 'Content-Type' => 'application/json' },
          body: {
            chat_id: chat_id,
            text: text,
            parse_mode: 'MarkdownV2'
          }.to_json,
          timeout: HTTP_TIMEOUT
        )

        if response.success?
          Rails.logger.info("[Zernio::AgentActionNotifier] notification sent chat=#{chat_id}")
          :ok
        else
          Rails.logger.warn(
            "[Zernio::AgentActionNotifier] Telegram HTTP #{response.code} body=#{response.body.to_s[0, 200]}"
          )
          :http_error
        end
      rescue StandardError => e
        Rails.logger.error("[Zernio::AgentActionNotifier] Telegram send failed: #{e.class}: #{e.message}")
        :exception
      end

      def bot_token
        ENV['TELEGRAM_BOT_TOKEN'].presence
      end

      def chat_id
        ENV.fetch('TELEGRAM_CASHOUT_GROUP_ID', '-5243223053')
      end

      def truncate_for_telegram(text)
        return '(empty)' if text.blank?

        truncated = text.to_s.length > TEXT_TRUNCATION_LIMIT ? "#{text.to_s[0, TEXT_TRUNCATION_LIMIT]}..." : text.to_s
        escape_markdown(truncated)
      end

      # MarkdownV2 requires escaping a long list of characters. Telegram
      # silently drops the message if any of them are unescaped inside the
      # body. We escape conservatively so user-supplied content can't break
      # the formatted notification.
      def escape_markdown(text)
        return '' if text.blank?

        text.to_s.gsub(/([_*\[\]()~`>#+\-=|{}.!\\])/, '\\\\\1')
      end
    end
  end
end
