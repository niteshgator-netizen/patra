class ActionCableBroadcastJob < ApplicationJob
  queue_as :critical
  include Events::Types

  CONVERSATION_UPDATE_EVENTS = [
    CONVERSATION_READ,
    CONVERSATION_UPDATED,
    TEAM_CHANGED,
    ASSIGNEE_CHANGED,
    CONVERSATION_STATUS_CHANGED
  ].freeze

  def perform(members, event_name, data)
    return if members.blank?

    broadcast_data = prepare_broadcast_data(event_name, data)
    return if broadcast_data.nil?

    broadcast_to_members(members, event_name, broadcast_data)
  end

  private

  # Ensures that only the latest available data is sent to prevent UI issues
  # caused by out-of-order events during high-traffic periods. This prevents
  # the conversation job from processing outdated data.
  def prepare_broadcast_data(event_name, data)
    return data unless CONVERSATION_UPDATE_EVENTS.include?(event_name)

    # patra-final 5a (G59): conversations with a nil display_id (or already
    # deleted records) made find_by!/find raise here and the job died —
    # 1,189 dead jobs piled up. A websocket refresh event is best-effort:
    # log and drop instead of dying.
    if data[:id].blank?
      Rails.logger.warn "ActionCableBroadcastJob: skipping #{event_name} — nil conversation display_id (account #{data[:account_id]})"
      return nil
    end

    account = Account.find(data[:account_id])
    conversation = account.conversations.find_by!(display_id: data[:id])
    conversation.push_event_data.merge(account_id: data[:account_id])
  rescue ActiveRecord::RecordNotFound
    Rails.logger.warn "ActionCableBroadcastJob: skipping #{event_name} — conversation #{data[:id]} / account #{data[:account_id]} not found"
    nil
  end

  def broadcast_to_members(members, event_name, broadcast_data)
    members.each do |member|
      ActionCable.server.broadcast(
        member,
        {
          event: event_name,
          data: broadcast_data
        }
      )
    end
  end
end
