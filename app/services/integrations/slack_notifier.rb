# frozen_string_literal: true

module Integrations
  class SlackNotifier
    EVENTS = %w[conversation.created sla.violation cashout.high_value].freeze

    def self.notify(account:, event:, payload: {})
      hook = account.hooks.find_by(app_id: 'slack')
      return unless hook

      text = format_message(event, payload)
      HTTParty.post(hook.settings['webhook_url'], body: { text: text }.to_json, headers: { 'Content-Type' => 'application/json' })
    rescue StandardError => e
      Rails.logger.error("[SlackNotifier] #{e.message}")
    end

    def self.format_message(event, payload)
      case event
      when 'conversation.created' then "New conversation ##{payload[:conversation_id]}"
      when 'sla.violation' then "SLA violation on conversation ##{payload[:conversation_id]}"
      when 'cashout.high_value' then "High-value cashout: $#{payload[:amount]}"
      else event
      end
    end
  end
end
