# frozen_string_literal: true

module PatraAuditHooks
  extend ActiveSupport::Concern

  included do
    after_update :patra_audit_message_changes, if: -> { is_a?(Message) }
    after_update :patra_audit_conversation_status, if: -> { is_a?(Conversation) }
    after_update :patra_audit_contact_update, if: -> { is_a?(Contact) }
    after_destroy :patra_audit_contact_delete, if: -> { is_a?(Contact) }
  end

  private

  def patra_audit_message_changes
    user = Current.user

    if saved_change_to_content? && outgoing? && sender_type == 'User'
      old_content = saved_changes['content']&.first.to_s
      Audit::Logger.log!(
        account: account,
        user: user,
        action: 'message_edited',
        target: self,
        metadata: { old_content: old_content, new_content: content }
      )
      Audit::TelegramNotifier.message_edited(message: self, old_content: old_content, editor_name: user&.name || 'Agent')
      Audit::DeceptionDetector.check_message_edit(self, user: user)
      Audit::DeceptionDetector.check_payment_amount_change(self, old_content: old_content, new_content: content, user: user)
    end

    return unless saved_change_to_content_attributes?

    prev_attrs, new_attrs = saved_change_to_content_attributes
    prev_deleted = prev_attrs.is_a?(Hash) ? prev_attrs['deleted'] || prev_attrs['is_deleted'] : nil
    new_deleted = new_attrs.is_a?(Hash) ? new_attrs['deleted'] || new_attrs['is_deleted'] : nil
    return unless new_deleted && !prev_deleted

    Audit::Logger.log!(account: account, user: user, action: 'message_deleted', target: self, metadata: { content: content })
    Audit::TelegramNotifier.message_deleted(message: self, deleted_content: content, deleter_name: user&.name || 'Agent')
    Audit::DeceptionDetector.check_message_delete(self, user: user)
  end

  def patra_audit_conversation_status
    return unless saved_change_to_status?

    action = resolved? ? 'conversation_resolved' : (status_before_last_save == 'resolved' ? 'conversation_reopened' : nil)
    return unless action

    Audit::Logger.log!(account: account, user: Current.user, action: action, target: self)
    Audit::DeceptionDetector.check_fast_resolve(self, user: Current.user) if action == 'conversation_resolved'
  end

  def patra_audit_contact_update
    Audit::Logger.log!(
      account: account,
      user: Current.user,
      action: 'contact_updated',
      target: self,
      metadata: { changed_keys: saved_changes.keys }
    )
  end

  def patra_audit_contact_delete
    Audit::Logger.log!(account: account, user: Current.user, action: 'contact_deleted', target: self, metadata: { name: name })
  end
end

ActiveSupport::Reloader.to_prepare do
  
  
  
end


ActiveSupport::Reloader.to_prepare do
  Message.include PatraAuditHooks
  Conversation.include PatraAuditHooks
  Contact.include PatraAuditHooks
end
