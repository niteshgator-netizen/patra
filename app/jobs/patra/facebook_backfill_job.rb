# frozen_string_literal: true

class Patra::FacebookBackfillJob < ApplicationJob
  queue_as :low
  sidekiq_options retry: 3

  def perform(inbox_id, opts = {})
    inbox = Inbox.find_by(id: inbox_id)
    return Rails.logger.warn("[PatraBackfill] inbox #{inbox_id} not found") unless inbox
    return Rails.logger.warn("[PatraBackfill] inbox #{inbox_id} not a Channel::Api") unless inbox.channel_type == 'Channel::Api'

    opts = opts.to_h.with_indifferent_access
    conversations_limit = (opts[:conversations_limit] || 50).to_i
    messages_limit = (opts[:messages_per_conversation_limit] || 25).to_i

    Rails.logger.info(
      "[PatraBackfill] starting inbox=#{inbox.id} convos_limit=#{conversations_limit} msgs_limit=#{messages_limit}"
    )

    Patra::FacebookBackfillService.new(
      inbox: inbox,
      conversations_limit: conversations_limit,
      messages_per_conversation_limit: messages_limit
    ).run!

    Rails.logger.info("[PatraBackfill] completed inbox=#{inbox.id}")
  end
end
