# frozen_string_literal: true

ActiveSupport::Reloader.to_prepare do
  Message.class_eval do
    after_create_commit :patra_run_message_automations

    def patra_run_message_automations
      Contacts::ReferralDetector.detect_and_store!(self)
      Conversations::AutoTagger.tag!(self)
      event = incoming? ? 'message.created.customer' : 'message.created.agent'
      Webhooks::OutboundDispatcher.dispatch(
        event,
        account: account,
        payload: { message_id: id, conversation_id: conversation_id }
      )
    end
  end

  Conversation.class_eval do
    after_create_commit :patra_run_conversation_automations

    def patra_run_conversation_automations
      Webhooks::OutboundDispatcher.dispatch(
        'conversation.created',
        account: account,
        payload: { conversation_id: id, contact_id: contact_id }
      )

      return if assignee_id.present?

      Assignment::RoundRobinService.new(account: account, inbox: inbox).assign_conversation(self)
    end

    after_update_commit :patra_webhook_on_resolve, if: :saved_change_to_status?

    def patra_webhook_on_resolve
      return unless resolved?

      Webhooks::OutboundDispatcher.dispatch(
        'conversation.resolved',
        account: account,
        payload: { conversation_id: id }
      )
    end
  end

  Contact.class_eval do
    after_create_commit :patra_webhook_on_create

    def patra_webhook_on_create
      Webhooks::OutboundDispatcher.dispatch(
        'contact.created',
        account: account,
        payload: { contact_id: id, name: name }
      )
    end
  end

  GameAction.class_eval do
    after_update_commit :patra_on_game_action_complete, if: :saved_change_to_status?

    def patra_on_game_action_complete
      return unless status == 'success'

      Webhooks::OutboundDispatcher.dispatch(
        'game_action.completed',
        account: account,
        payload: { game_action_id: id, action_type: action_type, amount: amount }
      )

      if action_type == 'load' && contact.present?
        Contacts::DepositCounter.record_load!(contact: contact, amount: amount)
        Webhooks::OutboundDispatcher.dispatch('payment.confirmed', account: account, payload: { type: 'load', amount: amount })
      elsif action_type == 'cashout' && contact.present?
        Contacts::DepositCounter.record_cashout!(contact: contact, amount: amount)
      end
    end
  end
end
