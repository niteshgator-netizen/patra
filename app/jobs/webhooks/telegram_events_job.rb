class Webhooks::TelegramEventsJob < ApplicationJob
  queue_as :default

  def perform(params = {})
    return unless params[:bot_token]
    return if duplicate_update?(params)

    channel = Channel::Telegram.find_by(bot_token: params[:bot_token])

    if channel_is_inactive?(channel)
      log_inactive_channel(channel, params)
      return
    end

    process_event_params(channel, params)
  end

  private

  # Telegram retries webhook deliveries; messages carry no unique constraint,
  # so a replayed update would create a duplicate. Dedup on update_id for 24h.
  # Fails OPEN (process the event) on any Redis error — losing a player message
  # is worse than a rare duplicate.
  def duplicate_update?(params)
    update_id = params.dig(:telegram, :update_id)
    return false if update_id.blank?

    token_part = Digest::SHA256.hexdigest(params[:bot_token].to_s)[0, 16]
    key = "patra:tg_update:#{token_part}:#{update_id}"
    first_time = Sidekiq.redis { |conn| conn.set(key, '1', nx: true, ex: 86_400) }
    if first_time
      false
    else
      Rails.logger.info("[TelegramEventsJob] duplicate update_id=#{update_id} skipped")
      true
    end
  rescue StandardError => e
    Rails.logger.warn("[TelegramEventsJob] dedup check failed (processing anyway): #{e.class}: #{e.message}")
    false
  end

  def channel_is_inactive?(channel)
    return true if channel.blank?
    return true unless channel.account.active?

    false
  end

  def log_inactive_channel(channel, params)
    message = if channel&.id
                "Account #{channel.account.id} is not active for channel #{channel.id}"
              else
                "Channel not found for bot_token: #{params[:bot_token]}"
              end
    Rails.logger.warn("Telegram event discarded: #{message}")
  end

  def process_event_params(channel, params)
    return unless params[:telegram]

    if params.dig(:telegram, :edited_message).present? || params.dig(:telegram, :edited_business_message).present?
      Telegram::UpdateMessageService.new(inbox: channel.inbox, params: params['telegram'].with_indifferent_access).perform
    else
      Telegram::IncomingMessageService.new(inbox: channel.inbox, params: params['telegram'].with_indifferent_access).perform
    end
  end
end
