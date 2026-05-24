# frozen_string_literal: true

module Sla
  class CheckViolationsJob < ApplicationJob
    queue_as :low

    def perform
      Account.find_each do |account|
        check_account(account)
      end
    end

    private

    def check_account(account)
      policies = account.sla_policies
      return if policies.blank?

      account.conversations.open.find_each do |conv|
        policy = conv.sla_policy || policies.first
        next unless policy

        check_first_response(conv, policy)
      end
    end

    def check_first_response(conversation, policy)
      threshold_minutes = policy.first_response_time_threshold.to_f
      return if threshold_minutes <= 0

      first_incoming = conversation.messages.incoming.order(:created_at).first
      return unless first_incoming

      first_reply = conversation.messages.outgoing.where('created_at > ?', first_incoming.created_at).order(:created_at).first
      return if first_reply

      waiting_minutes = ((Time.current - first_incoming.created_at) / 60.0).round
      return if waiting_minutes <= threshold_minutes

      metadata_key = "sla_violated_#{conversation.id}"
      return if Redis::Alfred.get(metadata_key)

      Redis::Alfred.set(metadata_key, '1', ex: 1.hour.to_i)

      Audit::TelegramNotifier.sla_violation(
        account: conversation.account,
        text: "🚨 SLA violated: Conversation ##{conversation.display_id} waiting #{waiting_minutes} minutes (limit: #{threshold_minutes.to_i})"
      )
    end
  end
end
