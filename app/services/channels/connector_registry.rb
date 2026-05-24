# frozen_string_literal: true

module Channels
  class ConnectorRegistry
    CONNECTORS = {
      'facebook' => Channels::Connectors::FacebookConnector,
      'instagram' => Channels::Connectors::InstagramConnector,
      'telegram' => Channels::Connectors::TelegramConnector,
      'sms' => Channels::Connectors::TwilioConnector,
      'email' => Channels::Connectors::EmailConnector,
      'web_widget' => Channels::Connectors::WebWidgetConnector
    }.freeze

    def self.for(inbox)
      channel_type = inbox.channel_type.demodulize.underscore
      connector_class = CONNECTORS[channel_type] || CONNECTORS['web_widget']
      connector_class.new(inbox)
    end

    def self.register(name, connector_class)
      CONNECTORS[name] = connector_class
    end
  end
end
