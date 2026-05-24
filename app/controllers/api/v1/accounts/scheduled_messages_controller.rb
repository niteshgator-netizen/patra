# frozen_string_literal: true

class Api::V1::Accounts::ScheduledMessagesController < Api::V1::Accounts::BaseController
  def index
    messages = Current.account.scheduled_messages
                      .where(conversation_id: params[:conversation_id])
                      .order(scheduled_at: :asc)
    render json: messages
  end

  def create
    message = Current.account.scheduled_messages.create!(
      conversation_id: params[:conversation_id],
      content: params[:content],
      scheduled_at: params[:scheduled_at],
      created_by_user: current_user,
      status: 'pending'
    )
    render json: message, status: :created
  end

  def destroy
    message = Current.account.scheduled_messages.find(params[:id])
    message.update!(status: 'cancelled')
    head :ok
  end
end
