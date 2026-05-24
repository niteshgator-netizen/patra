# frozen_string_literal: true

class Api::V1::Accounts::Patra::ReportsController < Api::V1::Accounts::BaseController
  before_action :check_authorization

  def show
    today_range = Time.current.beginning_of_day..Time.current
    week_range = 7.days.ago.beginning_of_day..Time.current
    yesterday_range = 1.day.ago.beginning_of_day..1.day.ago.end_of_day

    render json: {
      today: period_stats(today_range),
      this_week: period_stats(week_range),
      week_trend: {
        conversations: trend_delta(
          Current.account.conversations.where(created_at: today_range).count,
          Current.account.conversations.where(created_at: yesterday_range).count
        ),
        resolved: trend_delta(
          Current.account.conversations.where(status: :resolved, updated_at: today_range).count,
          Current.account.conversations.where(status: :resolved, updated_at: yesterday_range).count
        ),
        ai_handle_rate: trend_delta(
          calculate_ai_handle_rate(today_range),
          calculate_ai_handle_rate(yesterday_range)
        )
      },
      top_players: top_players(limit: 10),
      game_usage: game_usage_stats,
      payment_volume: payment_volume_by_day(days: 7),
      agent_performance: Analytics::AgentPerformanceService.new(Current.account, period: today_range).call,
      revenue_by_game: revenue_by_game,
      export_url: "/api/v1/accounts/#{Current.account.id}/patra/conversations/export"
    }
  end

  private

  def check_authorization
    authorize :report, :view?
  end

  def messages_scope
    Message.unscoped.where(account_id: Current.account.id, private: false)
  end

  def period_stats(period)
    {
      conversations_opened: Current.account.conversations.where(created_at: period).count,
      resolved: Current.account.conversations.where(status: :resolved, updated_at: period).count,
      ai_handle_rate: calculate_ai_handle_rate(period)
    }
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

  def trend_delta(current, previous)
    return { current: current, previous: previous, change: 0 } if previous.to_f.zero?

    { current: current, previous: previous, change: (((current.to_f - previous) / previous) * 100).round(1) }
  end

  def top_players(limit:)
    Current.account.conversations
           .where.not(contact_id: nil)
           .group(:contact_id)
           .order(Arel.sql('COUNT(*) DESC'))
           .limit(limit)
           .count
           .map do |contact_id, count|
      contact = Current.account.contacts.find_by(id: contact_id)
      {
        contact_id: contact_id,
        name: contact&.name || "Contact ##{contact_id}",
        conversations: count
      }
    end
  end

  def game_usage_stats
    actions = Current.account.game_actions
                     .joins(agent_game: :game)
                     .where(action_type: %w[load cashout], status: 'success')
                     .where('game_actions.created_at >= ?', 7.days.ago)

    loads = actions.where(action_type: 'load')
                   .group('games.slug', 'games.name')
                   .count
                   .map { |(slug, name), count| { slug: slug, name: name, loads: count } }

    cashouts = actions.where(action_type: 'cashout')
                      .group('games.slug', 'games.name')
                      .count
                      .map { |(slug, name), count| { slug: slug, name: name, cashouts: count } }

    slug_map = {}
    loads.each do |row|
      slug_map[row[:slug]] ||= { slug: row[:slug], name: row[:name], loads: 0, cashouts: 0 }
      slug_map[row[:slug]][:loads] = row[:loads]
    end
    cashouts.each do |row|
      slug_map[row[:slug]] ||= { slug: row[:slug], name: row[:name], loads: 0, cashouts: 0 }
      slug_map[row[:slug]][:name] ||= row[:name]
      slug_map[row[:slug]][:cashouts] = row[:cashouts]
    end

    slug_map.values.sort_by { |g| -(g[:loads] + g[:cashouts]) }
  end

  def payment_volume_by_day(days:)
    start_date = days.days.ago.beginning_of_day
    loads = Current.account.game_actions
                   .where(action_type: 'load', status: 'success')
                   .where('created_at >= ?', start_date)
                   .group(Arel.sql('DATE(created_at)'))
                   .sum(:amount)

    cashouts = Current.account.game_actions
                      .where(action_type: 'cashout', status: 'success')
                      .where('created_at >= ?', start_date)
                      .group(Arel.sql('DATE(created_at)'))
                      .sum(:amount)

    dates = ((Date.current - (days - 1))..Date.current).to_a
    dates.map do |date|
      key = date
      {
        date: date.to_s,
        deposits: loads[key].to_f.round(2),
        cashouts: cashouts[key].to_f.round(2)
      }
    end
  end

  def agent_performance_today
    Analytics::AgentPerformanceService.new(Current.account, period: Time.current.all_day).call
  end

  def revenue_by_game
    actions = Current.account.game_actions
                     .joins(agent_game: :game)
                     .where(action_type: %w[load cashout], status: 'success')
                     .where('game_actions.created_at >= ?', 30.days.ago)

    loads = actions.where(action_type: 'load').group('games.slug', 'games.name').sum(:amount)
    cashouts = actions.where(action_type: 'cashout').group('games.slug', 'games.name').sum(:amount)

    slugs = (loads.keys + cashouts.keys).uniq
    slugs.map do |(slug, name)|
      load_amt = loads[[slug, name]].to_f
      cash_amt = cashouts[[slug, name]].to_f
      { slug: slug, name: name, loads: load_amt.round(2), cashouts: cash_amt.round(2), net: (load_amt - cash_amt).round(2) }
    end.sort_by { |g| -g[:net] }
  end
end
