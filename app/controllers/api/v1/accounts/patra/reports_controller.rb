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
      agent_performance: Analytics::AgentPerformanceService.new(Current.account, period: agent_performance_range).call,
      revenue_by_game: revenue_by_game,
      conversation_volume_by_day: conversation_volume_by_day(days: 30),
      busiest_hours: busiest_hours,
      ai_vs_human_weekly: ai_vs_human_weekly,
      export_url: "/api/v1/accounts/#{Current.account.id}/patra/conversations/export"
    }
  end

  # 5d: daily/weekly sweepstakes money report. READ-ONLY aggregation over
  # GameAction — no code path here can move money. CSV via the existing
  # CSVSafe template pattern (see api/v2 reports).
  def sweeps
    range = sweeps_range
    @sweeps = sweeps_data(range)
    respond_to do |format|
      format.json { render json: @sweeps }
      format.csv do
        response.headers['Content-Type'] = 'text/csv'
        response.headers['Content-Disposition'] = "attachment; filename=sweepstakes_report_#{Date.current}.csv"
        render layout: false, template: 'api/v1/accounts/patra/reports/sweeps', formats: [:csv]
      end
    end
  end

  private

  def check_authorization
    authorize :report, :view?
  end

  def agent_performance_range
    case params[:agent_period].to_s
    when 'week' then 7.days.ago.beginning_of_day..Time.current
    when 'month' then 30.days.ago.beginning_of_day..Time.current
    else Time.current.beginning_of_day..Time.current
    end
  end

  def sweeps_range
    if params[:period].to_s == 'day'
      Time.current.beginning_of_day..Time.current
    else
      7.days.ago.beginning_of_day..Time.current
    end
  end

  def sweeps_data(range)
    scope = Current.account.game_actions.where(action_type: %w[load cashout], status: 'success', created_at: range)
    loads = scope.where(action_type: 'load')
    cashouts = scope.where(action_type: 'cashout')
    freeplay_loads = loads.where("COALESCE(metadata->>'freeplay', 'false') = 'true'")
    paid_loads = loads.where("COALESCE(metadata->>'freeplay', 'false') != 'true'")
    loads_total = loads.sum(:amount).to_f
    cashouts_total = cashouts.sum(:amount).to_f

    {
      period: params[:period].to_s == 'day' ? 'day' : 'week',
      from: range.begin.to_date.to_s,
      to: range.end.to_date.to_s,
      totals: {
        loads_count: loads.count,
        loads_total: loads_total.round(2),
        cashouts_count: cashouts.count,
        cashouts_total: cashouts_total.round(2),
        net: (loads_total - cashouts_total).round(2),
        freeplay_loads_count: freeplay_loads.count,
        freeplay_loads_total: freeplay_loads.sum(:amount).to_f.round(2),
        paid_loads_count: paid_loads.count,
        paid_loads_total: paid_loads.sum(:amount).to_f.round(2)
      },
      by_game: sweeps_by_game(scope),
      by_agent: sweeps_by_agent(scope),
      by_day: sweeps_by_day(loads, cashouts, range),
      game_trend: sweeps_game_trend
    }
  end

  # patra-final 6c (G10): loads/cashouts per ISO week per game, fixed 8-week
  # window (independent of the day/week toggle — a trend needs history).
  # READ-ONLY over GameAction like everything else here.
  GAME_TREND_WEEKS = 8

  def sweeps_game_trend
    start_at = (GAME_TREND_WEEKS - 1).weeks.ago.beginning_of_week
    sums = Current.account.game_actions
                  .joins(agent_game: :game)
                  .where(action_type: %w[load cashout], status: 'success')
                  .where('game_actions.created_at >= ?', start_at)
                  .group('games.name', :action_type, Arel.sql("DATE_TRUNC('week', game_actions.created_at)::date"))
                  .sum(:amount)

    weeks = (0...GAME_TREND_WEEKS).map { |i| (start_at + i.weeks).to_date }
    games = sums.keys.map(&:first).uniq.sort
    games.map do |game|
      {
        game: game,
        weeks: weeks.map do |week|
          {
            week: week.to_s,
            loads: sums[[game, 'load', week]].to_f.round(2),
            cashouts: sums[[game, 'cashout', week]].to_f.round(2)
          }
        end
      }
    end
  end

  def sweeps_by_game(scope)
    grouped = scope.joins(agent_game: :game).group('games.name', :action_type)
    counts = grouped.count
    sums = grouped.sum(:amount)
    games = counts.keys.map(&:first).uniq
    games.map do |game|
      load_total = sums[[game, 'load']].to_f
      cashout_total = sums[[game, 'cashout']].to_f
      {
        game: game,
        loads_count: counts[[game, 'load']].to_i,
        loads_total: load_total.round(2),
        cashouts_count: counts[[game, 'cashout']].to_i,
        cashouts_total: cashout_total.round(2),
        net: (load_total - cashout_total).round(2)
      }
    end.sort_by { |row| -row[:net] }
  end

  # Attribution follows the conversation assignee (GameAction carries no
  # executed-by column) — documented on the report page.
  def sweeps_by_agent(scope)
    grouped = scope.joins('INNER JOIN conversations ON conversations.id = game_actions.conversation_id')
                   .where.not(conversations: { assignee_id: nil })
                   .group('conversations.assignee_id', :action_type)
    counts = grouped.count
    sums = grouped.sum(:amount)
    ids = counts.keys.map(&:first).uniq
    names = User.where(id: ids).pluck(:id, :name).to_h
    ids.map do |id|
      load_total = sums[[id, 'load']].to_f
      cashout_total = sums[[id, 'cashout']].to_f
      {
        agent_id: id,
        agent: names[id] || "Agent ##{id}",
        loads_count: counts[[id, 'load']].to_i,
        loads_total: load_total.round(2),
        cashouts_count: counts[[id, 'cashout']].to_i,
        cashouts_total: cashout_total.round(2),
        net: (load_total - cashout_total).round(2)
      }
    end.sort_by { |row| -row[:loads_total] }
  end

  def sweeps_by_day(loads, cashouts, range)
    load_sums = loads.group(Arel.sql('DATE(created_at)')).sum(:amount)
    load_counts = loads.group(Arel.sql('DATE(created_at)')).count
    cashout_sums = cashouts.group(Arel.sql('DATE(created_at)')).sum(:amount)
    cashout_counts = cashouts.group(Arel.sql('DATE(created_at)')).count
    (range.begin.to_date..range.end.to_date).map do |date|
      {
        date: date.to_s,
        loads_count: load_counts[date].to_i,
        loads_total: load_sums[date].to_f.round(2),
        cashouts_count: cashout_counts[date].to_i,
        cashouts_total: cashout_sums[date].to_f.round(2),
        net: (load_sums[date].to_f - cashout_sums[date].to_f).round(2)
      }
    end
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

  # patra-final 6c (G12): weekly AI-vs-human reply trend, last 8 ISO weeks.
  # Marker mirrors calculate_ai_handle_rate's convention exactly: an outgoing
  # public message with sender_type 'User' is a human agent reply; any other
  # outgoing public message (AgentBot / nil sender) is the automated side.
  def ai_vs_human_weekly
    start_at = 7.weeks.ago.beginning_of_week
    week_sql = Arel.sql("DATE_TRUNC('week', created_at)::date")
    scope = messages_scope.outgoing.where('created_at >= ?', start_at)
    human = scope.where(sender_type: 'User').group(week_sql).count
    ai = scope.where("sender_type IS DISTINCT FROM 'User'").group(week_sql).count

    (0..7).map do |i|
      week = (start_at + i.weeks).to_date
      { week: week.to_s, human: human[week].to_i, ai: ai[week].to_i }
    end
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

  def conversation_volume_by_day(days:)
    start_date = days.days.ago.beginning_of_day
    counts = Current.account.conversations
                    .where('created_at >= ?', start_date)
                    .group(Arel.sql('DATE(created_at)'))
                    .count

    ((Date.current - (days - 1))..Date.current).map do |date|
      { date: date.to_s, count: counts[date].to_i }
    end
  end

  def busiest_hours
    start_date = 30.days.ago.beginning_of_day
    rows = Current.account.conversations
                  .where('created_at >= ?', start_date)
                  .pluck(Arel.sql('EXTRACT(DOW FROM created_at)::integer'), Arel.sql('EXTRACT(HOUR FROM created_at)::integer'))

    grid = Array.new(7) { Array.new(24, 0) }
    rows.each do |day, hour|
      grid[day][hour] += 1 if day && hour
    end

    { days: %w[Sun Mon Tue Wed Thu Fri Sat], hours: (0..23).to_a, grid: grid }
  end
end
