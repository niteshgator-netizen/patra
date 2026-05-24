# frozen_string_literal: true

module Audit
  class DeceptionDetector
    EDIT_THRESHOLD = 3
    EDIT_WINDOW = 1.hour
    DELETE_THRESHOLD = 5
    DELETE_WINDOW = 1.day
    FAST_RESOLVE_SECONDS = 30

    def self.check_message_edit(message, user:)
      return unless user

      count = AuditLog.where(account_id: message.account_id, user_id: user.id, action: 'message_edited')
                      .where('created_at >= ?', EDIT_WINDOW.ago)
                      .count
      return unless count >= EDIT_THRESHOLD

      flag!(account: message.account, user: user, reason: 'excessive_edits',
            metadata: { count: count, message_id: message.id })
    end

    def self.check_message_delete(message, user:)
      return unless user

      count = AuditLog.where(account_id: message.account_id, user_id: user.id, action: 'message_deleted')
                      .where('created_at >= ?', DELETE_WINDOW.ago)
                      .count
      return unless count >= DELETE_THRESHOLD

      flag!(account: message.account, user: user, reason: 'excessive_deletes',
            metadata: { count: count, message_id: message.id })
    end

    def self.check_payment_amount_change(message, old_content:, new_content:, user:)
      return unless user
      return unless payment_amount_changed?(old_content, new_content)

      flag!(account: message.account, user: user, reason: 'payment_amount_changed',
            metadata: { message_id: message.id, old_content: old_content, new_content: new_content })
    end

    def self.check_fast_resolve(conversation, user: nil)
      first_incoming = conversation.messages.incoming.order(:created_at).first
      return unless first_incoming

      elapsed = Time.current - first_incoming.created_at
      return unless elapsed <= FAST_RESOLVE_SECONDS

      flag!(account: conversation.account, user: user, reason: 'fast_resolve',
            metadata: { conversation_id: conversation.id, elapsed_seconds: elapsed.round })
    end

    def self.flag!(account:, user:, reason:, metadata: {})
      Audit::Logger.log!(
        account: account,
        user: user,
        action: 'deception_flag',
        metadata: metadata.merge(reason: reason)
      )

      agent_name = user&.name || 'Unknown'
      Audit::TelegramNotifier.deception_flag(
        account: account,
        text: "🚨 Deception flag: #{reason.tr('_', ' ')} by #{agent_name}\nDetails: #{metadata.to_json}"
      )
    end

    def self.payment_amount_changed?(old_content, new_content)
      old_amounts = extract_amounts(old_content)
      new_amounts = extract_amounts(new_content)
      old_amounts.any? && new_amounts.any? && old_amounts != new_amounts
    end

    def self.extract_amounts(text)
      text.to_s.scan(/\$\s?(\d+(?:\.\d{2})?)/).flatten.map(&:to_f).sort
    end
    private_class_method :extract_amounts
  end
end
