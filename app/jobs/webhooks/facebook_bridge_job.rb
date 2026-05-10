# Async worker that pushes one Facebook Messenger event into Chatwoot via the
# REST bridge. Two safety mechanisms protect us from duplicate ingestion:
#
#   1. Per-message dedupe: SET NX on a Redis key derived from the FB `mid`. The
#      first job to claim the mid wins; concurrent retries (from FB redelivery
#      or Sidekiq retries that finished after the bridge call but before the
#      job acked) become no-ops.
#   2. Per-sender mutex: serialises events from the same sender so two
#      messages arriving back-to-back can't race into two contacts / two
#      conversations. Falls back to retry on lock contention.
class Webhooks::FacebookBridgeJob < MutexApplicationJob
  queue_as :default
  retry_on LockAcquisitionError, wait: 1.second, attempts: 8

  PROCESSED_MID_KEY = 'FB_BOT_BRIDGE_PROCESSED::%<mid>s'.freeze
  PROCESSED_MID_TTL = 1.day.to_i
  SENDER_MUTEX_KEY = 'FB_BOT_BRIDGE_SENDER_LOCK::%<sender_id>s'.freeze
  SENDER_MUTEX_TIMEOUT = 30.seconds

  def perform(messaging)
    messaging = messaging.with_indifferent_access if messaging.respond_to?(:with_indifferent_access)
    mid = messaging.dig('message', 'mid').to_s
    sender_id = messaging.dig('sender', 'id').to_s

    if mid.present? && !claim_mid(mid)
      Rails.logger.info("[BotBridge] skipping duplicate mid=#{mid}")
      return
    end

    lock_key = format(SENDER_MUTEX_KEY, sender_id: sender_id)
    result = nil
    with_lock(lock_key, SENDER_MUTEX_TIMEOUT) do
      result = Facebook::ChatwootBridgeService.new(messaging).perform
    end

    # Trigger the AI auto-reply after the bridge has persisted the inbound
    # message. 3s delay gives Chatwoot a moment to fully commit the message
    # before we read the conversation history back out.
    if result.is_a?(Hash) && result[:conversation_id].present?
      Ai::ReplyJob.set(wait: 3.seconds).perform_later(result[:conversation_id])
    end
  rescue Facebook::ChatwootBridgeService::ConfigurationError => e
    # Misconfiguration won't fix itself by retrying — log loud and drop.
    Rails.logger.error("[BotBridge] configuration error mid=#{mid}: #{e.message}")
    release_mid(mid)
  rescue StandardError => e
    Rails.logger.error("[BotBridge] failed mid=#{mid} sender=#{sender_id} #{e.class}: #{e.message}")
    release_mid(mid)
    raise
  end

  private

  # SET NX EX returns truthy when we won the race, falsy when the key already
  # existed. We treat both `true` and the legacy `'OK'` reply as a successful
  # claim.
  def claim_mid(mid)
    result = Redis::Alfred.set(format(PROCESSED_MID_KEY, mid: mid), Time.now.to_i.to_s,
                               nx: true, ex: PROCESSED_MID_TTL)
    result == true || result == 'OK'
  end

  # Drop the dedupe key on failure so a future retry can take another swing.
  def release_mid(mid)
    return if mid.blank?

    Redis::Alfred.delete(format(PROCESSED_MID_KEY, mid: mid))
  rescue StandardError => e
    Rails.logger.warn("[BotBridge] failed to release mid=#{mid}: #{e.message}")
  end
end
