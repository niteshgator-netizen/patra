# frozen_string_literal: true

module Automation
  class TriggerDispatcher
    def self.dispatch(event, account:, conversation: nil, contact: nil, message: nil)
      trigger_type = map_event(event)
      return unless trigger_type

      flows = account.automation_flows.for_trigger(trigger_type)
      flows.find_each do |flow|
        next unless matches_trigger?(flow, conversation: conversation, contact: contact, message: message)

        Automation::FlowExecutor.new(
          flow: flow,
          conversation: conversation,
          contact: contact || conversation&.contact
        ).perform
      end
    end

    def self.map_event(event)
      {
        'message.received' => 'message_received',
        'conversation.opened' => 'conversation_opened',
        'contact.created' => 'contact_created',
        'tag.added' => 'tag_added',
        'lifecycle.changed' => 'lifecycle_changed'
      }[event.to_s]
    end

    def self.matches_trigger?(flow, conversation: nil, contact: nil, message: nil)
      config = flow.trigger_config || {}

      case flow.trigger_type
      when 'keyword_match', 'message_received'
        return false unless message

        keywords = Array(config['keywords'])
        content = message.content.to_s.downcase
        regex = config['regex']
        channel_ids = Array(config['channel_ids'])

        if channel_ids.any? && conversation
          return false unless channel_ids.include?(conversation.inbox_id.to_s)
        end

        return true if regex.present? && content.match?(Regexp.new(regex, Regexp::IGNORECASE))
        return true if keywords.any? { |kw| content.include?(kw.to_s.downcase) }

        flow.trigger_type == 'message_received'
      when 'conversation_opened'
        true
      when 'contact_created'
        contact.present?
      when 'schedule'
        false
      else
        true
      end
    end
  end
end
