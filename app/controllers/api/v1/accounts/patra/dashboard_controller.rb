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
      ai_handle_rate: Analytics::AiHandleRateService.new(Current.account, period: today).call[:rate],
      volume_by_channel: volume_by_channel(today),
      active_agents: active_agents,
      new_customers_today: Current.account.contacts.where(created_at: today).count,
      flagged_for_review: flagged_for_review_count,
      loads_today: load_cashout_stats(today)[:loads],
      cashouts_today: load_cashout_stats(today)[:cashouts],
      net_today: load_cashout_stats(today)[:net],
      game_performance: game_health_summary
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

  def flagged_for_review_count
    label_ids = ActsAsTaggableOn::Tag.where(name: %w[needs-human account-creation-failed]).pluck(:id)
    return 0 if label_ids.empty?

    Current.account.conversations.joins(:taggings)
           .where(taggings: { tag_id: label_ids, context: 'labels' })
           .distinct.count
  end

  def load_cashout_stats(period)
    loads = Current.account.game_actions.where(action_type: 'load', status: 'success', created_at: period)
    cashouts = Current.account.game_actions.where(action_type: 'cashout', status: 'success', created_at: period)
    load_amount = loads.sum(:amount).to_f
    cashout_amount = cashouts.sum(:amount).to_f
    {
      loads: { amount: load_amount.round(2), count: loads.count },
      cashouts: { amount: cashout_amount.round(2), count: cashouts.count },
      net: (load_amount - cashout_amount).round(2)
    }
  end

  def game_health_summary
    games = Current.account.agent_games.includes(:game)
    active = games.count { |g| g.failure_count.to_i < 3 }
    { active: active, total: games.size }
  end
end
