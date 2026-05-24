# frozen_string_literal: true

module Contacts
  class TimelineBuilder
    def initialize(contact)
      @contact = contact
    end

    def events
      items = []
      items += conversation_events
      items += game_action_events
      items += tag_events
      items.sort_by { |e| e[:at] }.reverse
    end

    private

    def conversation_events
      @contact.conversations.includes(:messages).flat_map do |conv|
        snippet = conv.messages.chat.last&.content.to_s.truncate(80)
        [{ type: 'conversation', at: conv.created_at, title: "Conversation ##{conv.id}", snippet: snippet }]
      end
    end

    def game_action_events
      GameAction.where(contact: @contact).map do |action|
        { type: 'game_action', at: action.created_at, title: "#{action.action_type} $#{action.amount}", snippet: action.game_username }
      end
    end

    def tag_events
      []
    end
  end
end
