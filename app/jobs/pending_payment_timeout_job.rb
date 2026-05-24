# frozen_string_literal: true

class PendingPaymentTimeoutJob < ApplicationJob
  queue_as :low

  PAYMENT_KEYWORDS = %w[payment send paid deposit load cashapp venmo paypal].freeze

  def perform
    Conversation.where(status: :open).find_each do |conv|
      attrs = conv.additional_attributes.to_h
      pending_at = parse_time(attrs['pending_payment_at'])
      next if pending_at.blank?

      next if pending_at > 30.minutes.ago

      last_msg = conv.messages.order(:created_at).last
      next if last_msg&.created_at && last_msg.created_at > pending_at

      Rails.logger.info(
        "[PendingPayment] reminder due conv=#{conv.id} pending_since=#{pending_at.iso8601}"
      )
    end
  end

  def self.mark_pending!(conversation)
    text = conversation.messages.incoming.order(:created_at).last&.content.to_s.downcase
    return unless PAYMENT_KEYWORDS.any? { |kw| text.include?(kw) }

    attrs = conversation.additional_attributes.to_h
    attrs['pending_payment_at'] = Time.current.iso8601
    conversation.update!(additional_attributes: attrs)
  rescue StandardError => e
    Rails.logger.error("[PendingPayment] mark failed conv=#{conversation.id}: #{e.message}")
  end

  private

  def parse_time(value)
    return if value.blank?

    Time.zone.parse(value.to_s)
  rescue ArgumentError
    nil
  end
end
