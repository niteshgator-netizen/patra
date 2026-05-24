# frozen_string_literal: true

class ReengageDormantContactsJob < ApplicationJob
  queue_as :low

  def perform
    Account.find_each do |account|
      days = account.custom_attributes&.dig('reengage_days') || 7
      cutoff = days.days.ago

      dormant = account.contacts
                       .joins(:conversations)
                       .where('conversations.last_activity_at < ?', cutoff)
                       .where(conversations: { status: Conversation.statuses[:resolved] })
                       .distinct

      dormant.find_each do |contact|
        Rails.logger.info("[Reengage] would message contact=#{contact.id} account=#{account.id}")
      end
    end
  end
end
