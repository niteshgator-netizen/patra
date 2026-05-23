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

      ActiveRecord::Base.transaction do
        persist_channel_platform!
        contact_inbox = find_or_create_contact_inbox
        conversation = find_or_create_conversation(contact_inbox)
        message = create_message(conversation, contact_inbox.contact)
        Rails.logger.info("[ZernioDispatcher] created message=#{message.id} conv=#{conversation.id} inbox=#{inbox.id}")
        message
      end
    rescue StandardError => e
      Rails.logger.error("[ZernioDispatcher] failed inbox=#{inbox.id} #{e.class}: #{e.message}")
      raise
    end

    private

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

    def duplicate_message?
      return false if parsed[:external_message_id].blank?

      inbox.messages.exists?(source_id: parsed[:external_message_id])
    end

    def find_or_create_contact_inbox
      sender_id = parsed[:sender_id].to_s

      ContactInboxWithContactBuilder.new(
        source_id: sender_id,
        inbox: inbox,
        contact_attributes: {
          name: parsed[:sender_name].presence || "Zernio User #{sender_id}",
          identifier: sender_id,
          additional_attributes: { zernio_sender_id: sender_id }
        }
      ).perform
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
