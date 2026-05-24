# frozen_string_literal: true

class Api::V1::Accounts::Patra::ConversationsController < Api::V1::Accounts::BaseController
  before_action :set_conversation

  def toggle_pin
    attrs = @conversation.additional_attributes.to_h
    attrs['pinned'] = !ActiveModel::Type::Boolean.new.cast(attrs['pinned'])
    @conversation.update!(additional_attributes: attrs)
    render json: { pinned: attrs['pinned'] }
  end

  private

  def set_conversation
    @conversation = Current.account.conversations.find(params[:conversation_id])
    authorize @conversation, :update?
  end
end
