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
    rescue StandardError => e
      # One bad conversation must not kill the sweep (or the stuck-action alert below).
      Rails.logger.error("[PendingPayment] conv=#{conv.id} #{e.class}: #{e.message}")
    end

    alert_stuck_game_actions
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

  # GameActions stuck 'pending' >1h mean a load/cashout started and never
  # resolved — a human needs to look. Alert via Telegram, throttled once/hour
  # (setex pattern). READ-ONLY: no GameAction state is ever mutated here.
  def alert_stuck_game_actions
    stuck = GameAction.where(status: 'pending')
                      .where('created_at < ?', 1.hour.ago)
                      .order(:created_at)
                      .limit(50)
                      .to_a
    return if stuck.empty?

    Rails.logger.warn("[PendingPayment] #{stuck.size} GameActions stuck pending >1h ids=#{stuck.map(&:id).inspect}")

    redis = Redis.new(Redis::Config.app)
    throttle_key = 'patra:stuck_pending_alert'
    return if redis.get(throttle_key).present?

    redis.setex(throttle_key, 1.hour.to_i, '1')

    stuck.group_by(&:account_id).each do |account_id, actions|
      lines = actions.map do |a|
        hours = ((Time.current - a.created_at) / 1.hour).round(1)
        "##{a.id} #{a.action_type} $#{a.amount} #{a.game_username} (#{hours}h)"
      end
      Games::TelegramNotifier.api_error(
        account: Account.find_by(id: account_id),
        message: "#{actions.size} game action(s) stuck PENDING >1h — needs a human look",
        details: lines.join("\n")
      )
    end
  rescue StandardError => e
    # Alerting must never break the sweep itself.
    Rails.logger.error("[PendingPayment] stuck-action alert failed: #{e.class}: #{e.message}")
  end

  def parse_time(value)
    return if value.blank?

    Time.zone.parse(value.to_s)
  rescue ArgumentError
    nil
  end
end
