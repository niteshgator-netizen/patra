class Notification::RemoveDuplicateNotificationJob < ApplicationJob
  queue_as :default

  def perform(notification)
    return unless notification.is_a?(Notification)

    user_id = notification.user_id
    primary_actor_id = notification.primary_actor_id
    # patra-final P3: scope by actor TYPE too — without it, a Conversation
    # and a PatraAgentFeedback sharing the same numeric id counted as
    # duplicates and one user's notification silently vanished.
    primary_actor_type = notification.primary_actor_type

    # Find older notifications with the same user and primary actor
    duplicate_notifications = Notification.where(user_id: user_id, primary_actor_type: primary_actor_type,
                                                 primary_actor_id: primary_actor_id)
                                          .order(created_at: :desc)

    # Skip the first one (the latest notification) and destroy the rest
    duplicate_notifications.offset(1).each(&:destroy)
  end
end
