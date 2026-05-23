# frozen_string_literal: true

module Webhooks
  class ZernioController < ActionController::API
    SUPPORTED_EVENTS = %w[
      message.received message.sent message.delivered
      message.read message.edited message.deleted
      message.failed
      account.connected account.disconnected
    ].freeze

    def create
      raw_body = request.body.read

      unless verify_signature(raw_body)
        Rails.logger.warn("[ZernioWebhook] signature verification failed ip=#{request.remote_ip}")
        return head :unauthorized
      end

      payload = JSON.parse(raw_body)
      event = payload['event'].to_s

      unless SUPPORTED_EVENTS.include?(event)
        Rails.logger.info("[ZernioWebhook] unknown event=#{event} — acking")
        return head :ok
      end

      case event
      when 'message.received'
        ProcessZernioInboundJob.perform_later(payload)
      when 'message.edited'
        handle_message_edited(payload)
      when 'message.deleted'
        handle_message_deleted(payload)
      when 'message.delivered'
        handle_delivery_status(payload, 'delivered')
      when 'message.read'
        handle_delivery_status(payload, 'read')
      when 'message.failed'
        # Real Zernio webhook shape uses top-level `message` / `conversation`
        # keys (verified against production logs in Phase F). The previous
        # `payload['data']` lookup was a stale guess that always logged nil.
        Rails.logger.error(
          "[ZernioWebhook] message.failed " \
          "message=#{payload['message']&.slice('id', 'conversationId', 'platform').inspect} " \
          "conversation=#{payload['conversation']&.slice('id').inspect}"
        )
      else
        # message.sent / account.* — ack only for now
        Rails.logger.info("[ZernioWebhook] ack event=#{event}")
      end

      head :ok
    rescue JSON::ParserError => e
      Rails.logger.error("[ZernioWebhook] invalid JSON: #{e.message}")
      head :bad_request
    rescue StandardError => e
      Rails.logger.error("[ZernioWebhook] #{e.class}: #{e.message}\n#{e.backtrace.first(5).join("\n")}")
      head :internal_server_error
    end

    private

    # Apply a customer-side edit: record the prior content in a structured
    # edit_history audit list, bump edit_count, then update the message body
    # to the new text. UI can render an "(edited)" badge by reading
    # content_attributes['is_edited'].
    def handle_message_edited(payload)
      Thread.current[:zernio_webhook_update] = true
      zernio_message_id = payload.dig('message', 'id')
      return if zernio_message_id.blank?

      message = find_message_by_zernio_id(zernio_message_id)
      unless message
        Rails.logger.info("[ZernioWebhook] message.edited unknown msg_id=#{zernio_message_id}")
        return
      end

      new_text = payload.dig('message', 'text').to_s
      old_text = message.content

      attrs = message.content_attributes.to_h
      edit_history = Array(attrs['edit_history']).dup
      edit_history << { 'old_text' => old_text, 'edited_at' => Time.current.iso8601 }

      attrs['edit_history'] = edit_history
      attrs['is_edited'] = true
      attrs['edited_at'] = Time.current.iso8601
      attrs['edit_count'] = edit_history.length

      message.update!(content: new_text, content_attributes: attrs)
      Rails.logger.info("[ZernioWebhook] message.edited msg=#{message.id} edits=#{attrs['edit_count']}")
    rescue StandardError => e
      Rails.logger.error(
        "[ZernioWebhook] message.edited failed zernio_id=#{zernio_message_id} #{e.class}: #{e.message}"
      )
    ensure
      Thread.current[:zernio_webhook_update] = nil
    end

    # Soft-delete: flag the message via content_attributes; the original
    # content is preserved on the Message row so an agent investigating
    # later can still see what was sent. UI renders the "[deleted]"
    # placeholder by branching on content_attributes['is_deleted'].
    def handle_message_deleted(payload)
      Thread.current[:zernio_webhook_update] = true
      zernio_message_id = payload.dig('message', 'id')
      return if zernio_message_id.blank?

      message = find_message_by_zernio_id(zernio_message_id)
      unless message
        Rails.logger.info("[ZernioWebhook] message.deleted unknown msg_id=#{zernio_message_id}")
        return
      end

      attrs = message.content_attributes.to_h
      attrs['is_deleted'] = true
      attrs['deleted_at'] = payload['timestamp'].presence || payload['deletedAt'].presence || Time.current.iso8601

      message.update!(content_attributes: attrs)
      Rails.logger.info("[ZernioWebhook] message.deleted msg=#{message.id}")
    rescue StandardError => e
      Rails.logger.error(
        "[ZernioWebhook] message.deleted failed zernio_id=#{zernio_message_id} #{e.class}: #{e.message}"
      )
    ensure
      Thread.current[:zernio_webhook_update] = nil
    end

    # Apply a delivery / read receipt: update message.status via the
    # canonical Messages::StatusUpdateService (which drives Chatwoot's
    # existing check-mark UI and guards against invalid transitions, e.g.
    # 'delivered' arriving after 'read'). Also stamp a per-status timestamp
    # into content_attributes for audit (delivered_at / read_at).
    def handle_delivery_status(payload, status)
      zernio_message_id = payload.dig('message', 'id')
      return if zernio_message_id.blank?

      message = find_message_by_zernio_id(zernio_message_id)
      unless message
        Rails.logger.debug { "[ZernioWebhook] message.#{status} unknown msg_id=#{zernio_message_id}" }
        return
      end

      applied = Messages::StatusUpdateService.new(message, status).perform
      unless applied
        Rails.logger.info("[ZernioWebhook] message.#{status} rejected for msg=#{message.id} (invalid transition)")
        return
      end

      attrs = message.content_attributes.to_h
      attrs["#{status}_at"] = payload['timestamp'].presence || payload['statusAt'].presence || Time.current.iso8601
      message.update!(content_attributes: attrs)

      Rails.logger.info("[ZernioWebhook] message.#{status} msg=#{message.id}")
    rescue StandardError => e
      Rails.logger.error(
        "[ZernioWebhook] message.#{status} failed zernio_id=#{zernio_message_id} #{e.class}: #{e.message}"
      )
    end

    # Resolve a Zernio message id to a Patra Message AR. Phase D inbound and
    # the upcoming history sync (Bucket H.4) both store the raw Zernio id as
    # `source_id` — the indexed exact-match is the production fast path.
    # Falls back to a JSONB scan against content_attributes for older paths
    # that may have stashed the id only inside the JSONB blob.
    def find_message_by_zernio_id(zernio_id)
      return nil if zernio_id.blank?

      Message.find_by(source_id: zernio_id.to_s) ||
        Message.where("content_attributes->>'zernio_message_id' = ?", zernio_id.to_s).first
    end

    def verify_signature(raw_body)
      signature = request.headers['X-Zernio-Signature']
      secret = ENV['ZERNIO_WEBHOOK_SECRET']
      return false if signature.blank? || secret.blank?

      expected = OpenSSL::HMAC.hexdigest('SHA256', secret, raw_body)
      ActiveSupport::SecurityUtils.secure_compare(signature.to_s, expected)
    rescue StandardError => e
      Rails.logger.error("[ZernioWebhook] signature check error: #{e.message}")
      false
    end
  end
end
