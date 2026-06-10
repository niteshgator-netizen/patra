# frozen_string_literal: true

class Widget::MessagesController < ActionController::API
  before_action :set_web_widget

  def create
    contact = find_or_create_contact
    conversation = find_or_create_conversation(contact)
    message = Messages::MessageBuilder.new(nil, conversation, {
      content: params[:content],
      private: false,
      sender: contact
    }).perform

    render json: { message_id: message.id, conversation_id: conversation.id }
  end

  private

  def set_web_widget
    @web_widget = Channel::WebWidget.find_by!(website_token: params[:website_token])
    # PATRA TAB-C (ADM7): suspended accounts must not accept public widget
    # traffic — mirrors widgets_controller.rb's existing suspension check.
    render json: { error: 'Account is suspended' }, status: :unauthorized unless @web_widget.account.active?
  end

  def find_or_create_contact
    email = params[:email].presence || "widget-#{SecureRandom.hex(4)}@patra.local"
    ContactInboxWithContactBuilder.new({
      source_id: email,
      inbox: @web_widget.inbox,
      contact_attributes: { name: params[:name], email: email }
    }).perform.contact
  end

  def find_or_create_conversation(contact)
    contact_inbox = ContactInbox.find_by!(contact: contact, inbox: @web_widget.inbox)
    contact.conversations.find_by(inbox: @web_widget.inbox) ||
      Conversation.create!(account: @web_widget.account, inbox: @web_widget.inbox, contact: contact, contact_inbox: contact_inbox)
  end
end
