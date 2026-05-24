# frozen_string_literal: true

class AutoResolveStaleConversationsJob < ApplicationJob
  queue_as :low

  def perform
    stale = Conversation.where(status: :open)
                        .where('last_activity_at < ?', 24.hours.ago)

    count = 0
    stale.find_each do |conv|
      conv.update!(status: :resolved)
      count += 1
      Rails.logger.info("[AutoResolve] resolved conv=#{conv.id} last_activity=#{conv.last_activity_at}")
    end

    Rails.logger.info("[AutoResolve] resolved #{count} stale conversations")
  end
end
