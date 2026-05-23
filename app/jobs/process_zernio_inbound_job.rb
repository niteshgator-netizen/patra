# frozen_string_literal: true

class ProcessZernioInboundJob < ApplicationJob
  queue_as :default

  retry_on StandardError, wait: :exponentially_longer, attempts: 5

  PROCESSED_EVENT_KEY = 'ZERNIO_WEBHOOK_PROCESSED::%<event_id>s'
  PROCESSED_EVENT_TTL = 1.day.to_i

  def perform(payload)
    event_id = payload['id'].to_s

    if event_id.present? && !claim_event_id(event_id)
      Rails.logger.info("[ZernioJob] duplicate event_id=#{event_id} skipping")
      return
    end

    account_section = payload['account'] || {}
    zernio_account_id = account_section['id'] || account_section['accountId']

    if zernio_account_id.blank?
      Rails.logger.warn("[ZernioJob] payload missing account.id payload_keys=#{payload.keys.inspect}")
      return
    end

    inbox = find_inbox_by_zernio_account(zernio_account_id)

    unless inbox
      Rails.logger.warn("[ZernioJob] no inbox for zernio accountId=#{zernio_account_id}")
      return
    end

    parsed = Messaging::BaseProvider.for(inbox).parse_inbound(payload)
    Messaging::InboundDispatcher.new(inbox: inbox, parsed: parsed).perform
  rescue StandardError => e
    release_event_id(event_id)
    Rails.logger.error("[ZernioJob] inbox lookup or dispatch failed: #{e.class}: #{e.message}")
    raise
  end

  private

  # Mirrors Webhooks::FacebookBridgeJob#claim_mid using Redis::Alfred SET NX
  # with a 24h TTL. Returns true when we won the claim (first to see this
  # event_id) and false when the key already exists (duplicate replay).
  # Degrades OPEN on Redis errors: if Redis is unreachable we proceed as if
  # newly claimed — the DB-level Messaging::InboundDispatcher#duplicate_message?
  # check is the belt-and-suspenders fallback specified for Bucket E-1.
  def claim_event_id(event_id)
    result = Redis::Alfred.set(
      format(PROCESSED_EVENT_KEY, event_id: event_id),
      Time.now.to_i.to_s,
      nx: true,
      ex: PROCESSED_EVENT_TTL
    )
    result == true || result == 'OK'
  rescue StandardError => e
    Rails.logger.warn("[ZernioJob] redis claim failed event_id=#{event_id} #{e.class}: #{e.message}; degrading open")
    true
  end

  # Drops the dedup key on failure so a future Sidekiq retry can re-claim.
  # Mirrors Webhooks::FacebookBridgeJob#release_mid exactly. Best-effort —
  # a Redis error here is logged and swallowed (the retry will just dedup
  # itself out on the next attempt if Redis comes back).
  def release_event_id(event_id)
    return if event_id.blank?

    Redis::Alfred.delete(format(PROCESSED_EVENT_KEY, event_id: event_id))
  rescue StandardError => e
    Rails.logger.warn("[ZernioJob] redis release failed event_id=#{event_id}: #{e.message}")
  end

  def find_inbox_by_zernio_account(zernio_account_id)
    Inbox.where(messaging_provider: 'zernio').find do |i|
      i.channel&.additional_attributes&.dig('zernio_account_id') == zernio_account_id
    end
  end
end
