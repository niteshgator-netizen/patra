# frozen_string_literal: true

module Messaging
  class BaseProvider
    attr_reader :inbox

    def initialize(inbox)
      @inbox = inbox
    end

    def send_message(conversation_id:, text: nil, attachments: [])
      raise NotImplementedError, "#{self.class.name} must implement #send_message"
    end

    def verify_webhook(headers:, body:)
      raise NotImplementedError, "#{self.class.name} must implement #verify_webhook"
    end

    def parse_inbound(payload)
      raise NotImplementedError, "#{self.class.name} must implement #parse_inbound"
    end

    def connect_url(callback_url:)
      raise NotImplementedError, "#{self.class.name} must implement #connect_url"
    end

    def disconnect!
      raise NotImplementedError, "#{self.class.name} must implement #disconnect!"
    end

    class << self
      def for(inbox)
        case inbox.messaging_provider
        when 'direct_meta' then Messaging::DirectMetaProvider.new(inbox)
        when 'zernio'      then Messaging::ZernioProvider.new(inbox)
        else raise "Unknown messaging provider: #{inbox.messaging_provider.inspect}"
        end
      end
    end
  end

  class SendError < StandardError; end
  class TransientSendError < SendError; end
  class PermanentSendError < SendError; end
  class WebhookVerificationError < StandardError; end
end
