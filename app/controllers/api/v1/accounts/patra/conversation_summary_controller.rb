# frozen_string_literal: true

class Api::V1::Accounts::Patra::ConversationSummaryController < Api::V1::Accounts::BaseController
  before_action :set_conversation

  def show
    messages = @conversation.messages.where.not(content: [nil, '']).order(:created_at).limit(50)
    summary = Ai::ConversationSummaryService.new(messages).call
    render json: { summary: summary }
  end

  private

  def set_conversation
    @conversation = Current.account.conversations.find(params[:conversation_id])
    authorize @conversation, :show?
  end
end
