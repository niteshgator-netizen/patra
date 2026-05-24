# frozen_string_literal: true

module Integrations
  class CalendarService
    def initialize(account:, user:)
      @account = account
      @user = user
    end

    def schedule_follow_up(conversation:, title:, datetime:, provider: 'google')
      event = {
        title: title,
        datetime: datetime,
        provider: provider,
        conversation_id: conversation.id,
        contact_id: conversation.contact_id
      }
      attrs = conversation.custom_attributes || {}
      events = Array(attrs['scheduled_events'])
      events << event
      attrs['scheduled_events'] = events
      conversation.update!(custom_attributes: attrs)
      event
    end

    def upcoming_events(conversation)
      Array(conversation.custom_attributes.to_h['scheduled_events']).select do |e|
        Time.parse(e['datetime']) > Time.current
      rescue ArgumentError
        false
      end
    end
  end
end
