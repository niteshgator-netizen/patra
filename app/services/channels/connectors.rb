# frozen_string_literal: true

module Channels
  module Connectors
    class BaseConnector
      def initialize(inbox)
        @inbox = inbox
        @channel = inbox.channel
      end

      def send_message(conversation:, text:, attachments: [])
        raise NotImplementedError
      end

      def handle_webhook(payload)
        raise NotImplementedError
      end

      def validate_credentials
        true
      end
    end

    class FacebookConnector < BaseConnector
      def send_message(conversation:, text:, attachments: [])
        Messaging::OutboundDispatcher.send(inbox: @inbox, conversation: conversation, text: text, attachments: attachments)
      end

      def handle_webhook(payload)
        Facebook::MessageHandler.new(payload).process if defined?(Facebook::MessageHandler)
      end
    end

    class InstagramConnector < BaseConnector
      def send_message(conversation:, text:, attachments: [])
        Instagram::MessageHandler.send_outbound(inbox: @inbox, conversation: conversation, text: text)
      end

      def handle_webhook(payload)
        Instagram::MessageHandler.new(payload).process
      end
    end

    class TelegramConnector < BaseConnector
      def send_message(conversation:, text:, attachments: [])
        Telegram::CustomerBotHandler.send_message(inbox: @inbox, conversation: conversation, text: text)
      end

      def handle_webhook(payload)
        Telegram::CustomerBotHandler.new(payload, inbox: @inbox).process
      end
    end

    class TwilioConnector < BaseConnector
      def send_message(conversation:, text:, attachments: [])
        Twilio::SmsHandler.send_outbound(inbox: @inbox, conversation: conversation, text: text)
      end

      def handle_webhook(payload)
        Twilio::SmsHandler.new(payload, inbox: @inbox).process
      end
    end

    class EmailConnector < BaseConnector
      def send_message(conversation:, text:, attachments: [])
        conversation.messages.create!(account: @inbox.account, inbox: @inbox, content: text, message_type: :outgoing)
      end

      def handle_webhook(payload)
        Channels::EmailPollJob.perform_later(@inbox.id)
      end
    end

    class WebWidgetConnector < BaseConnector
      def send_message(conversation:, text:, attachments: [])
        conversation.messages.create!(account: @inbox.account, inbox: @inbox, content: text, message_type: :outgoing)
      end

      def handle_webhook(_payload)
        true
      end
    end
  end
end
