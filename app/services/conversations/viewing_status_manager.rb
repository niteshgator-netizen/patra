# Collision detection (4b): announces that an agent has a conversation open.
# Mirrors TypingStatusManager — same dispatcher, same listener fan-out — so
# other agents see "X is viewing" before they walk into the same conversation.
class Conversations::ViewingStatusManager
  include Events::Types

  attr_reader :conversation, :user, :params

  def initialize(conversation, user, params)
    @conversation = conversation
    @user = user
    @params = params
  end

  def trigger_viewing_event(event)
    Rails.configuration.dispatcher.dispatch(event, Time.zone.now, conversation: @conversation, user: @user)
  end

  def toggle_viewing_status
    case params[:viewing_status]
    when 'on'
      trigger_viewing_event(CONVERSATION_VIEWING_ON)
    when 'off'
      trigger_viewing_event(CONVERSATION_VIEWING_OFF)
    end
  end
end
