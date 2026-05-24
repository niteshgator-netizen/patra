# frozen_string_literal: true

ActiveSupport::Reloader.to_prepare do
  Message.class_eval do
    after_create_commit :patra_dispatch_automation_triggers, if: :incoming?

    def patra_dispatch_automation_triggers
      Automation::TriggerDispatcher.dispatch(
        'message.received',
        account: account,
        conversation: conversation,
        contact: conversation&.contact,
        message: self
      )
    end
  end

  Conversation.class_eval do
    after_create_commit :patra_dispatch_conversation_opened

    def patra_dispatch_conversation_opened
      Automation::TriggerDispatcher.dispatch(
        'conversation.opened',
        account: account,
        conversation: self,
        contact: contact
      )
    end
  end

  Contact.class_eval do
    after_create_commit :patra_dispatch_contact_created

    def patra_dispatch_contact_created
      Automation::TriggerDispatcher.dispatch(
        'contact.created',
        account: account,
        contact: self
      )
    end
  end
end
