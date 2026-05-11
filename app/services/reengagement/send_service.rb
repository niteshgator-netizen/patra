# frozen_string_literal: true

module Reengagement
  class SendService
    BLOCKED_LABELS = %w[ai-off do-not-message].freeze
    LAST_REENGAGEMENT_ATTR = 'last_reengagement_date'.freeze

    def initialize(contact:, skip_dormancy_check: false)
      @contact = contact
      @skip_dormancy_check = skip_dormancy_check
    end

    def call
      return skipped(:blocked) if @contact.blocked?
      return skipped(:blocked_labels) if blocked_by_labels?
      return skipped(:loyalty_tier) unless eligible_loyalty_tier?
      return skipped(:recent_reengagement) if within_reengagement_cooldown?

      conversation = resolve_facebook_conversation
      return skipped(:no_messenger_conversation) if conversation.blank?
      return skipped(:channel_disconnected) if conversation.inbox.channel.reauthorization_required?

      last_incoming = last_incoming_message_at(conversation)
      if !@skip_dormancy_check && (last_incoming.blank? || last_incoming >= 7.days.ago)
        return skipped(:not_dormant)
      end

      content = MessagePicker.message_for(@contact)
      Messages::MessageBuilder.new(
        nil,
        conversation,
        { content: content, private: false }
      ).perform

      record_reengagement_timestamp!
      { ok: true }
    rescue StandardError => e
      ChatwootExceptionTracker.new(e, account: @contact.account).capture_exception
      { ok: false, reason: :error }
    end

    private

    def blocked_by_labels?
      (@contact.label_list.map(&:downcase) & BLOCKED_LABELS).any?
    end

    def eligible_loyalty_tier?
      tier = @contact.custom_attributes['loyalty_tier'].to_s.strip.downcase
      tier.present? && tier != 'new'
    end

    def within_reengagement_cooldown?
      raw = @contact.custom_attributes[LAST_REENGAGEMENT_ATTR]
      return false if raw.blank?

      parsed = parse_reengagement_date(raw)
      return false if parsed.blank?

      parsed >= 14.days.ago.to_date
    end

    def parse_reengagement_date(raw)
      Date.iso8601(raw.to_s)
    rescue ArgumentError
      nil
    end

    def record_reengagement_timestamp!
      attrs = @contact.custom_attributes.merge(LAST_REENGAGEMENT_ATTR => Time.zone.today.iso8601)
      @contact.update!(custom_attributes: attrs)
    end

    def resolve_facebook_conversation
      scope = facebook_messenger_conversations
      convs = scope.to_a
      return if convs.blank?

      qualified =
        if @skip_dormancy_check
          convs
        else
          convs.select do |c|
            t = last_incoming_message_at(c)
            t.present? && t < 7.days.ago
          end
        end

      pool = qualified.presence || convs
      pool.max_by(&:last_activity_at)
    end

    def facebook_messenger_conversations
      @contact.conversations
              .joins(inbox: :channel)
              .where(inboxes: { channel_type: 'Channel::FacebookPage' })
              .where("(conversations.additional_attributes->>'type') IS DISTINCT FROM ?", 'instagram_direct_message')
    end

    def last_incoming_message_at(conversation)
      conversation.messages
                  .where(message_type: :incoming, private: false, sender_type: 'Contact')
                  .maximum(:created_at)
    end

    def skipped(reason)
      { ok: false, reason: reason }
    end
  end
end
