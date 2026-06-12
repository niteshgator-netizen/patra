# frozen_string_literal: true

# patra-final P3: agents create + list their own feedback; admins see all,
# filter by category/status, and mark entries seen.
class Api::V1::Accounts::PatraAgentFeedbacksController < Api::V1::Accounts::BaseController
  def index
    scope = Current.account.patra_agent_feedbacks
    scope = scope.where(user_id: Current.user.id) unless current_user_admin?
    scope = scope.where(category: params[:category]) if valid_category?
    scope = scope.where(status: params[:status]) if valid_status?

    feedbacks = scope.order(created_at: :desc).limit(200)
    render json: feedbacks.map { |feedback| serialize(feedback) }
  end

  def create
    feedback = Current.account.patra_agent_feedbacks.new(
      user: Current.user,
      body: params[:body].to_s.strip,
      category: valid_category? ? params[:category] : 'other',
      conversation: find_conversation,
      contact: find_contact
    )

    if feedback.save
      render json: serialize(feedback)
    else
      render json: { errors: feedback.errors.full_messages }, status: :unprocessable_entity
    end
  end

  # Admin-only: mark seen / back to new.
  def update
    return render_unauthorized('Only administrators can update feedback') unless current_user_admin?

    feedback = Current.account.patra_agent_feedbacks.find(params[:id])
    return render json: { errors: ['Invalid status'] }, status: :unprocessable_entity unless valid_status?

    feedback.update!(status: params[:status])
    render json: serialize(feedback)
  end

  private

  def current_user_admin?
    Current.account_user&.administrator?
  end

  def valid_category?
    PatraAgentFeedback.categories.key?(params[:category].to_s)
  end

  def valid_status?
    PatraAgentFeedback.statuses.key?(params[:status].to_s)
  end

  # The dashboard works with conversation display ids.
  def find_conversation
    return if params[:conversation_id].blank?

    Current.account.conversations.find_by(display_id: params[:conversation_id])
  end

  def find_contact
    return if params[:contact_id].blank?

    Current.account.contacts.find_by(id: params[:contact_id])
  end

  def serialize(feedback)
    {
      id: feedback.id,
      body: feedback.body,
      category: feedback.category,
      status: feedback.status,
      user: { id: feedback.user_id, name: feedback.user&.name },
      conversation_display_id: feedback.conversation&.display_id,
      contact: feedback.contact && { id: feedback.contact.id, name: feedback.contact.name },
      created_at: feedback.created_at
    }
  end
end
