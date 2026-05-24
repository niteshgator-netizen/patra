# frozen_string_literal: true

class Api::V1::Accounts::Patra::DashboardController < Api::V1::Accounts::BaseController
  before_action :check_authorization

  def show
    today = Time.current.beginning_of_day..Time.current

    stats = {
      conversations_today: Current.account.conversations.where(created_at: today).count,
      messages_in_today: messages_scope.incoming.where(created_at: today).count,
      messages_out_today: messages_scope.outgoing.where(created_at: today).count,
      resolved_today: Current.account.conversations.where(status: :resolved, updated_at: today).count,
      ai_handle_rate: calculate_ai_handle_rate(today),
      volume_by_channel: volume_by_channel(today),
      active_agents: active_agents,
      game_performance: { status: 'coming_soon' }
    }

    render json: stats
  end

  private

  def check_authorization
    authorize :report, :view?
  end

  def messages_scope
    Message.unscoped.where(account_id: Current.account.id, private: false)
  end

  def calculate_ai_handle_rate(period)
    total = Current.account.conversations.where(created_at: period).count
    return 0 if total.zero?

    human_conv_ids = messages_scope.outgoing
                                   .where(created_at: period)
                                   .where(sender_type: 'User')
                                   .distinct
                                   .pluck(:conversation_id)

    ai_only = Current.account.conversations
                     .where(created_at: period, status: :resolved)
                     .where.not(id: human_conv_ids)
                     .count

    ((ai_only.to_f / total) * 100).round(1)
  end

  def volume_by_channel(period)
    Current.account.conversations
           .where(created_at: period)
           .joins(:inbox)
           .group('inboxes.name')
           .count
  end

  def active_agents
    Current.account.account_users
           .where(availability: :online)
           .includes(:user)
           .map { |au| { name: au.user.name, role: au.role } }
  end
end
