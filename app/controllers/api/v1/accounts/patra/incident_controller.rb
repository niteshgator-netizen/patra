# frozen_string_literal: true

class Api::V1::Accounts::Patra::IncidentController < Api::V1::Accounts::BaseController
  def pause_ai
    attrs = Current.account.custom_attributes || {}
    attrs['ai_paused'] = true
    Current.account.update!(custom_attributes: attrs)
    render json: { ai_paused: true }
  end

  def broadcast_open
    message = params[:message]
    count = 0
    Current.account.conversations.open.find_each do |conv|
      user = current_user
      Messages::MessageBuilder.new(user, conv, { content: message, private: false }).perform
      count += 1
    end
    render json: { sent: count }
  end

  def reassign_all
    from_user = Current.account.users.find(params[:from_user_id])
    to_user = Current.account.users.find(params[:to_user_id])
    updated = Current.account.conversations.where(assignee: from_user).update_all(assignee_id: to_user.id)
    render json: { reassigned: updated }
  end
end
