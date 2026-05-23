# frozen_string_literal: true

module Messaging
  class InboundDispatcher
    attr_reader :inbox, :parsed

    def initialize(inbox:, parsed:)
      @inbox = inbox
      @parsed = parsed.with_indifferent_access
    end

    def perform
      return if duplicate_message?
      return if parsed[:sender_id].blank?

      conversation = nil
      message = nil

      ActiveRecord::Base.transaction do
        persist_channel_platform!
        contact_inbox = find_or_create_contact_inbox
        enrich_contact!(contact_inbox.contact)
        conversation = find_or_create_conversation(contact_inbox)
        message = create_message(conversation, contact_inbox.contact)
        persist_message_attachments!(message)
        Rails.logger.info("[ZernioDispatcher] created message=#{message.id} conv=#{conversation.id} inbox=#{inbox.id}")
      end

      enqueue_ai_reply(conversation) if conversation
      message
    rescue StandardError => e
      Rails.logger.error("[ZernioDispatcher] failed inbox=#{inbox.id} #{e.class}: #{e.message}")
      raise
    end

    private

    # Mirrors Webhooks::FacebookBridgeJob's AI enqueue exactly: positional
    # args (display_id, account_id, fb_shaped_attachments) with a 3-second
    # delay so AR commits land before Ai::ReplyService reads the conversation
    # history back over Chatwoot's REST API. Best-effort — failure to enqueue
    # never blocks ingestion (the agent UI already has the inbound message).
    def enqueue_ai_reply(conversation)
      Ai::ReplyJob.set(wait: 3.seconds).perform_later(
        conversation.display_id,
        conversation.account_id,
        fb_shaped_attachments
      )
      Rails.logger.info(
        "[ZernioDispatcher] enqueued Ai::ReplyJob conv=#{conversation.display_id} account=#{conversation.account_id}"
      )
    rescue StandardError => e
      Rails.logger.error(
        "[ZernioDispatcher] AI enqueue failed conv=#{conversation&.display_id} #{e.class}: #{e.message}"
      )
    end

    # Pass parsed attachments through unchanged. Ai::ReplyService accepts
    # both { type, url } and { type, payload: { url } } shapes and filters
    # out anything else, so this is safe for the text-only inbound we have
    # today. Bucket B-inbound (verifying Zernio's actual image-webhook
    # payload shape and mapping it into Patra Attachment records) is
    # deferred pending a real image-event sample.
    def fb_shaped_attachments
      Array(parsed[:attachments])
    end

    # Write-once persistence: the first inbound webhook for a Zernio channel
    # records the underlying platform (facebook/instagram/whatsapp/telegram)
    # on the channel so the sidebar can render the correct icon. Idempotent —
    # subsequent webhooks skip if already set, and silent no-op if the payload
    # doesn't carry a platform value.
    def persist_channel_platform!
      platform = parsed[:platform].to_s.presence
      return if platform.blank?

      channel = inbox.channel
      return unless channel.respond_to?(:additional_attributes)

      attrs = channel.additional_attributes.to_h
      return if attrs['zernio_platform'].present?

      attrs['zernio_platform'] = platform
      channel.update!(additional_attributes: attrs)
      Rails.logger.info("[ZernioDispatcher] persisted zernio_platform=#{platform} on channel=#{channel.id} inbox=#{inbox.id}")
    rescue StandardError => e
      Rails.logger.warn("[ZernioDispatcher] failed to persist zernio_platform inbox=#{inbox.id}: #{e.class}: #{e.message}")
    end

    # Persist inbound Zernio attachments as Patra Attachment records using
    # external_url (no download). FB CDN URLs expire ~24h via the `oe=`
    # signed param — acceptable for Phase G; Cloudinary permanent storage
    # is a future phase.
    #
    # Best-effort: each attachment creation is wrapped in begin/rescue so a
    # single bad item never blocks the rest, and an outer rescue ensures
    # any structural surprise (e.g. parsed[:attachments] not being an Array)
    # doesn't roll back the transaction. The message itself is already
    # persisted before this runs.
    def persist_message_attachments!(message)
      Array(parsed[:attachments]).each do |att|
        next if att.blank?

        att_h = att.respond_to?(:with_indifferent_access) ? att.with_indifferent_access : att
        att_type = att_h['type'].to_s.downcase
        att_url = att_h['url'].presence || att_h.dig('payload', 'url').presence

        if att_url.blank?
          Rails.logger.warn("[ZernioDispatcher] attachment missing url inbox=#{inbox.id} type=#{att_type.inspect}")
          next
        end

        file_type = map_zernio_attachment_type(att_type)

        begin
          message.attachments.create!(
            account_id: inbox.account_id,
            file_type: file_type,
            external_url: att_url
          )
          Rails.logger.info(
            "[ZernioDispatcher] stored attachment inbox=#{inbox.id} conv=#{message.conversation_id} " \
            "type=#{file_type} external_url_present=true"
          )
        rescue StandardError => e
          Rails.logger.warn(
            "[ZernioDispatcher] attachment store failed inbox=#{inbox.id} type=#{att_type.inspect} " \
            "#{e.class}: #{e.message}"
          )
        end
      end
    rescue StandardError => e
      Rails.logger.warn(
        "[ZernioDispatcher] attachment loop crashed inbox=#{inbox.id} #{e.class}: #{e.message}; message kept"
      )
    end

    # Maps Zernio's attachment `type` field to Patra's Attachment.file_type
    # enum (see app/models/attachment.rb line 43). Unknown types fall back
    # to :file so the URL is still preserved and downloadable from the UI.
    def map_zernio_attachment_type(att_type)
      case att_type
      when 'image', 'photo'   then :image
      when 'video'            then :video
      when 'audio', 'voice'   then :audio
      when 'file', 'document' then :file
      else :file
      end
    end

    def duplicate_message?
      return false if parsed[:external_message_id].blank?

      inbox.messages.exists?(source_id: parsed[:external_message_id])
    end

    def find_or_create_contact_inbox
      sender_id = parsed[:sender_id].to_s
      attrs = Messaging::ZernioContactEnrichment.contact_attributes_from_inbound(parsed)

      ContactInboxWithContactBuilder.new(
        source_id: sender_id,
        inbox: inbox,
        contact_attributes: {
          name: attrs[:name],
          identifier: attrs[:identifier],
          avatar_url: attrs[:avatar_url],
          additional_attributes: attrs[:additional_attributes]
        }
      ).perform
    end

    def enrich_contact!(contact)
      Messaging::ZernioContactEnrichment.enrich_contact!(contact, parsed)
    end

    def find_or_create_conversation(contact_inbox)
      external_id = parsed[:conversation_id].to_s

      existing = inbox.conversations
                      .where(contact_inbox_id: contact_inbox.id, identifier: external_id)
                      .where.not(status: :resolved)
                      .first
      return existing if existing

      if inbox.lock_to_single_conversation
        open_conv = contact_inbox.conversations.where.not(status: :resolved).last
        return open_conv if open_conv
      end

      Conversation.create!(
        account_id: inbox.account_id,
        inbox_id: inbox.id,
        contact_id: contact_inbox.contact_id,
        contact_inbox_id: contact_inbox.id,
        identifier: external_id,
        additional_attributes: {
          external_conversation_id: external_id,
          messaging_provider: 'zernio',
          platform: parsed[:platform]
        }
      )
    end

    def create_message(conversation, contact)
      conversation.messages.create!(
        account_id: inbox.account_id,
        inbox_id: inbox.id,
        message_type: :incoming,
        content: parsed[:text].presence || '[no text]',
        source_id: parsed[:external_message_id],
        sender: contact,
        status: :sent,
        content_attributes: {
          zernio_platform: parsed[:platform],
          zernio_timestamp: parsed[:timestamp]
        }.compact
      )
    end
  end
end
