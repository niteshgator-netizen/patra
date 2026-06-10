# frozen_string_literal: true

class Api::V1::Accounts::Patra::DashboardController < Api::V1::Accounts::BaseController
  before_action :check_authorization

  def show
    period = resolve_period(params[:range])
    money = load_cashout_stats(period) # one pass — was computed 3x (12 queries -> 4)

    stats = {
      conversations_today: Current.account.conversations.where(created_at: period).count,
      messages_in_today: messages_scope.incoming.where(created_at: period).count,
      messages_out_today: messages_scope.outgoing.where(created_at: period).count,
      resolved_today: Current.account.conversations.where(status: :resolved, updated_at: period).count,
      ai_handle_rate: Analytics::AiHandleRateService.new(Current.account, period: period).call[:rate],
      escalation_rate: escalation_rate(period),
      still_open_rate: still_open_rate(period),
      volume_by_channel: volume_by_channel(period),
      active_agents: active_agents,
      new_customers_today: Current.account.contacts.where(created_at: period).count,
      flagged_for_review: flagged_for_review_count,
      loads_today: money[:loads],
      cashouts_today: money[:cashouts],
      net_today: money[:net],
      game_performance: game_health_summary,
      heatmap: heatmap_data,
      top_questions: top_questions_for(period)
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

  def resolve_period(range)
    case range
    when '7d'  then 7.days.ago.beginning_of_day..Time.current
    when '30d' then 30.days.ago.beginning_of_day..Time.current
    else            Time.current.beginning_of_day..Time.current
    end
  end

  def escalation_rate(period)
    total = Current.account.conversations.where(created_at: period).count
    return 0 if total.zero?

    escalated = messages_scope.outgoing
                              .where(created_at: period, sender_type: 'User')
                              .distinct.pluck(:conversation_id).size
    ((escalated.to_f / total) * 100).round(1)
  end

  def still_open_rate(period)
    total = Current.account.conversations.where(created_at: period).count
    return 0 if total.zero?

    open_count = Current.account.conversations.where(created_at: period, status: :open).count
    ((open_count.to_f / total) * 100).round(1)
  end

  def heatmap_data
    start = 7.days.ago.beginning_of_day
    rows = Current.account.conversations
                  .where(created_at: start..Time.current)
                  .group("EXTRACT(DOW FROM created_at AT TIME ZONE 'UTC')",
                         "EXTRACT(HOUR FROM created_at AT TIME ZONE 'UTC')")
                  .count
    rows.map { |(dow, hour), count| { dow: dow.to_i, hour: hour.to_i, count: count } }
  end

  def top_questions_for(period)
    conv_ids = Message.unscoped.where(
      account_id: Current.account.id,
      message_type: :outgoing,
      source_id: OwnerStats::Aggregator::AI_SOURCE_ID,
      created_at: period
    ).distinct.pluck(:conversation_id)
    return [] if conv_ids.empty?

    handled_ids = Current.account.conversations
                         .where(id: conv_ids)
                         .where("COALESCE(cached_label_list, '') NOT LIKE ?", '%needs-human%')
                         .pluck(:id)
    return [] if handled_ids.empty?

    texts = Message.unscoped.where(
      account_id: Current.account.id,
      conversation_id: handled_ids,
      message_type: :incoming,
      private: false,
      created_at: period
    ).where.not(content: [nil, '']).pluck(:content)

    rows = texts.map { |c| c.to_s.strip.truncate(80, omission: '...') }
                .reject(&:blank?)
                .tally
                .sort_by { |_text, n| -n }
                .first(5)
    max = rows.map(&:last).max || 1
    rows.map do |text, count|
      {
        question: text,
        count: count,
        pct: ((count.to_f / max) * 100).round
      }
    end
  end
end
