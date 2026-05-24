# frozen_string_literal: true

class SuperAdmin::PatraDashboardController < SuperAdmin::ApplicationController
  def show
    render json: {
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
    ActiveRecord::Base.connection.execute("SELECT pg_size_pretty(pg_database_size(current_database()))").first['pg_size_pretty']
  rescue StandardError
    'unknown'
  end

  def game_health_status
    Game.all.map { |g| { slug: g.slug, status: g.status } }
  rescue StandardError
    []
  end
end
