class Api::V1::Accounts::Captain::TasksController < Api::V1::Accounts::BaseController
  before_action :check_authorization

  def rewrite
    if xai_available?
      content = params[:content].to_s.strip
      return render json: { message: content } if content.blank?

      api_key = ENV['XAI_API_KEY']
      response = HTTParty.post(
        'https://api.x.ai/v1/chat/completions',
        headers: { 'Authorization' => "Bearer #{api_key}", 'Content-Type' => 'application/json' },
        body: {
          model: ENV.fetch('XAI_MODEL', 'grok-4.3'),
          max_tokens: 200,
          messages: [{
            role: 'user',
            content: "#{params[:operation] || 'Improve'} this customer service message. Keep it under 2 lines, friendly, human. Return only the rewritten text:\n\n#{content}"
          }]
        }.to_json,
        timeout: 8
      )
      msg = response.success? ? response.parsed_response.dig('choices', 0, 'message', 'content') : content
      return render json: { message: msg || content }
    end

    result = Captain::RewriteService.new(
      account: Current.account,
      content: params[:content],
      operation: params[:operation],
      conversation_display_id: params[:conversation_display_id]
    ).perform

    render_result(result)
  end

  def summarize
    if xai_available?
      conversation = Current.account.conversations
                           .find_by(display_id: params[:conversation_display_id])
      return render json: { message: nil } unless conversation

      messages = conversation.messages
                             .where(message_type: [0, 1])
                             .order(:created_at)
                             .last(30)
      summary = Ai::ConversationSummaryService.new(messages).call
      return render json: { message: summary }
    end

    result = Captain::SummaryService.new(
      account: Current.account,
      conversation_display_id: params[:conversation_display_id]
    ).perform

    render_result(result)
  end

  def reply_suggestion
    if xai_available?
      conversation = Current.account.conversations
                           .find_by(display_id: params[:conversation_display_id])
      return render json: { message: nil } unless conversation

      last_customer_msg = conversation.messages
                                      .where(message_type: 0)
                                      .order(:created_at)
                                      .last
      return render json: { message: nil } unless last_customer_msg

      suggestion = Bella::QuickRephrase.call(
        customer_text: last_customer_msg.content.to_s,
        hint_reply: 'How can I help you today?',
        conversation_id: conversation.id
      )
      return render json: { message: suggestion || 'No suggestion available.' }
    end

    result = Captain::ReplySuggestionService.new(
      account: Current.account,
      conversation_display_id: params[:conversation_display_id],
      user: Current.user
    ).perform

    render_result(result)
  end

  def label_suggestion
    result = Captain::LabelSuggestionService.new(
      account: Current.account,
      conversation_display_id: params[:conversation_display_id]
    ).perform

    render_result(result)
  end

  def follow_up
    result = Captain::FollowUpService.new(
      account: Current.account,
      follow_up_context: params[:follow_up_context]&.to_unsafe_h,
      user_message: params[:message],
      conversation_display_id: params[:conversation_display_id]
    ).perform

    render_result(result)
  end

  private

  def xai_available?
    ENV['XAI_API_KEY'].present?
  end

  def render_result(result)
    if result.nil?
      render json: { message: nil }
    elsif result[:error]
      render json: { error: result[:error] }, status: :unprocessable_content
    else
      response_data = { message: result[:message] }
      response_data[:follow_up_context] = result[:follow_up_context] if result[:follow_up_context]
      render json: response_data
    end
  end

  def check_authorization
    authorize(:'captain/tasks')
  end
end

Api::V1::Accounts::Captain::TasksController.prepend_mod_with('Api::V1::Accounts::Captain::TasksController')
