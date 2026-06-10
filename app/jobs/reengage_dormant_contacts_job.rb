# frozen_string_literal: true

class ReengageDormantContactsJob < ApplicationJob
  queue_as :low

  def perform
    Account.find_each do |account|
      # to_i: settings may persist reengage_days as a string — "14".days raises
      days = (account.custom_attributes&.dig('reengage_days') || 7).to_i
      days = 7 if days <= 0
      cutoff = days.days.ago

      dormant = account.contacts
                       .joins(:conversations)
                       .where('conversations.last_activity_at < ?', cutoff)
                       .where(conversations: { status: Conversation.statuses[:resolved] })
                       .distinct

      dormant.find_each do |contact|
        Rails.logger.info("[Reengage] would message contact=#{contact.id} account=#{account.id}")
      end
    rescue StandardError => e
      # One bad account must not kill the whole sweep.
      Rails.logger.error("[ReengageDormantContactsJob] account=#{account.id} #{e.class}: #{e.message}")
    end
  end
end
