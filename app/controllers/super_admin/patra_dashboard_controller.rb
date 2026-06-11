# frozen_string_literal: true

# ADM1: Patra platform command center. Super-admin-gated (devise, via
# SuperAdmin::ApplicationController), READ-ONLY — no mutating action exists
# in this controller. All aggregations are SQL group queries or the batched
# finance scan in Patra::FinanceAnalytics (zero per-account N+1).
class SuperAdmin::PatraDashboardController < SuperAdmin::ApplicationController
  VALID_QUICK_RANGES = [7, 30, 90].freeze

  def show
    respond_to do |format|
      format.html do
        @range = date_range
        @range_days = range_days
        @accounts_panel = accounts_panel
        @engagement = engagement_panel
        @money = Patra::FinanceAnalytics.platform_scan(range: @range)
        @integrations = integrations_panel
        @billing = billing_panel
        # Read-only list feeding the quick-action selects; the actions
        # themselves POST to PatraAccounts/PatraImpersonations controllers.
        @accounts_for_actions = Account.order(:name).limit(200)
        @actions_enabled = Patra::AdminConsole.actions_enabled?
        render :show
      end
      format.json { render json: legacy_summary } # pre-ADM1 JSON contract kept
    end
  end

  def system_health
    render json: {
      sidekiq: sidekiq_stats,
      redis_memory: redis_info,
      db_size: db_size,
      game_health: game_health_status,
      last_errors: AuditLog.where('created_at > ?', 24.hours.ago).order(created_at: :desc).limit(20)
    }
  end

  private

  # ---- date range -------------------------------------------------------

  def date_range
    custom = custom_range
    return custom if custom

    range_days.days.ago.beginning_of_day..Time.zone.now.end_of_day
  end

  def range_days
    VALID_QUICK_RANGES.include?(params[:days].to_i) ? params[:days].to_i : 30
  end

  def custom_range
    return nil if params[:from].blank? || params[:to].blank?

    from = safe_date(params[:from])
    to = safe_date(params[:to])
    return nil unless from && to && from <= to

    from.beginning_of_day..to.end_of_day
  end

  def safe_date(value)
    Date.parse(value.to_s)
  rescue ArgumentError, TypeError
    nil
  end

  # ---- panels ------------------------------------------------------------

  def accounts_panel
    {
      total: Account.count,
      by_status: Account.group(:status).count,
      signups_7d: Account.where(created_at: 7.days.ago..).count,
      signups_30d: Account.where(created_at: 30.days.ago..).count,
      signups_90d: Account.where(created_at: 90.days.ago..).count,
      signup_trend: Account.where(created_at: @range).group('DATE(accounts.created_at)').count.sort.to_h
    }
  end

  # Mirrors OwnerStats::Aggregator definitions, platform-wide and in pure SQL:
  # AI-handled = conversations with an 'ai_auto' outgoing message and no
  # needs-human label; handoff = conversations labeled needs-human.
  def engagement_panel
    incoming = Message.unscoped.where(message_type: :incoming, private: false, created_at: @range)
    conv_with_incoming = incoming.distinct.count(:conversation_id)

    escalated = Conversation.where(id: incoming.select(:conversation_id))
                            .where("COALESCE(cached_label_list, '') LIKE ?", '%needs-human%')
                            .count

    non_escalated = Conversation.where(id: incoming.select(:conversation_id))
                                .where("COALESCE(cached_label_list, '') NOT LIKE ?", '%needs-human%')
    ai_handled = Message.unscoped
                        .where(message_type: :outgoing, source_id: 'ai_auto', created_at: @range)
                        .where(conversation_id: non_escalated.select(:id))
                        .distinct.count(:conversation_id)

    {
      conversations_created: Conversation.where(created_at: @range).count,
      conversations_with_player_messages: conv_with_incoming,
      ai_handled_percent: percent(ai_handled, conv_with_incoming),
      handoff_rate_percent: percent(escalated, conv_with_incoming)
    }
  end

  def integrations_panel
    down_by_game = AgentGame.joins(:game)
                            .where(agent_games: { failure_count: Patra::GameHealthQuery::DOWN_FAILURE_THRESHOLD.. })
                            .group('games.name').count
    {
      total_connections: AgentGame.count,
      active_connections: AgentGame.where(status: 'active').count,
      down_total: down_by_game.values.sum,
      down_by_game: down_by_game
    }
  end

  # Defensive: billing tables don't exist yet (logged in PATRA_FEAT_LOG.md).
  # When patra_billing_subscriptions ships, this panel lights up with a row
  # count; MRR stays '—' until the column shape is known (TODO-CONFIG).
  def billing_panel
    return { initialized: false } unless ActiveRecord::Base.connection.data_source_exists?('patra_billing_subscriptions')

    {
      initialized: true,
      subscriptions: ActiveRecord::Base.connection.select_value('SELECT COUNT(*) FROM patra_billing_subscriptions').to_i,
      mrr: nil
    }
  rescue StandardError
    { initialized: false }
  end

  def percent(part, whole)
    return 0.0 if whole.to_i.zero?

    ((part.to_f / whole) * 100).round(1)
  end

  # ---- legacy JSON (pre-ADM1 contract) ------------------------------------

  def legacy_summary
    {
      total_accounts: Account.count,
      total_conversations: Conversation.count,
      total_messages: Message.count,
      active_accounts: Account.where('updated_at > ?', 7.days.ago).count,
      dormant_accounts: Account.where('updated_at <= ?', 30.days.ago).count,
      sidekiq_queue_depth: sidekiq_stats[:enqueued],
      failed_jobs: sidekiq_stats[:dead],
      feature_flags: FeatureFlag.all
    }
  end

  def sidekiq_stats
    stats = Sidekiq::Stats.new
    { enqueued: stats.enqueued, dead: stats.dead_size, processed: stats.processed, failed: stats.failed }
  rescue StandardError
    { enqueued: 0, dead: 0 }
  end

  def redis_info
    Redis.new.info['used_memory_human']
  rescue StandardError
    'unknown'
  end

  def db_size
    ActiveRecord::Base.connection.execute('SELECT pg_size_pretty(pg_database_size(current_database()))').first['pg_size_pretty']
  rescue StandardError
    'unknown'
  end

  def game_health_status
    Game.all.map { |g| { slug: g.slug, status: g.status } }
  rescue StandardError
    []
  end
end
