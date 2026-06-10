# frozen_string_literal: true

module Sla
  class CheckViolationsJob < ApplicationJob
    queue_as :low

    # How long the once-per-conversation resolution alert stamp survives.
    RESOLUTION_STAMP_TTL = 7.days

    def perform
      Account.find_each do |account|
        check_account(account)
      rescue StandardError => e
        # One bad account must not kill the whole sweep.
        Rails.logger.error("[Sla::CheckViolationsJob] account=#{account.id} #{e.class}: #{e.message}")
      end
    end

    private

    def check_account(account)
      attrs = (account.custom_attributes || {}).stringify_keys
      # Settings -> "SLA alerts" toggle (default true when unset)
      return if attrs.key?('sla_alerts_enabled') && ActiveModel::Type::Boolean.new.cast(attrs['sla_alerts_enabled']) == false

      policies = account.sla_policies
      custom_limits = attrs['first_response_limit_minutes'].present? || attrs['resolution_limit_minutes'].present?
      return if policies.blank? && !custom_limits

      account.conversations.open.find_each do |conv|
        policy = conv.sla_policy || policies.first

        check_first_response(conv, policy, attrs)
        check_resolution(conv, policy, attrs)
      end
    end

    def check_first_response(conversation, policy, attrs)
      threshold_minutes = (attrs['first_response_limit_minutes'].presence || policy&.first_response_time_threshold).to_f
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

    # Mirror of check_first_response for the resolution limit: an OPEN
    # conversation whose first inbound message is older than the limit.
    # Alerts once per conversation (durable stamp, no hourly re-alert).
    def check_resolution(conversation, policy, attrs)
      threshold_minutes = (attrs['resolution_limit_minutes'].presence || policy&.resolution_time_threshold).to_f
      return if threshold_minutes <= 0

      first_incoming = conversation.messages.incoming.order(:created_at).first
      return unless first_incoming

      open_minutes = ((Time.current - first_incoming.created_at) / 60.0).round
      return if open_minutes <= threshold_minutes

      metadata_key = "sla_resolution_violated_#{conversation.id}"
      return if Redis::Alfred.get(metadata_key)

      Redis::Alfred.set(metadata_key, '1', ex: RESOLUTION_STAMP_TTL.to_i)

      Audit::TelegramNotifier.sla_violation(
        account: conversation.account,
        text: "🚨 SLA violated: Conversation ##{conversation.display_id} unresolved for #{open_minutes} minutes (limit: #{threshold_minutes.to_i})"
      )
    end
  end
end
