# frozen_string_literal: true

module OwnerStats
  # Aggregates Patra owner dashboard metrics for the Reports overview.
  # Finance rows: contact custom_attributes["patra_finance_logs"] as
  # [{ "kind" => "deposit"|"cashout", "amount" => 12.34, "logged_at" => ISO8601 }, ...]
  class Aggregator
    AI_SOURCE_ID = 'ai_auto'
    FINANCE_LOG_KEY = 'patra_finance_logs'

    def initialize(account)
      @account = account
      @tz = ActiveSupport::TimeZone[account.reporting_timezone.presence] || Time.zone
      @now = @tz.now
    end

    def call
      {
        today: period_payload(today_range),
        this_week: period_payload(this_week_range),
        growth_vs_previous_week: growth_payload,
        players: players_payload,
        ai_performance: ai_performance_payload(this_week_range)
      }
    end

    private

    def period_payload(range)
      {
        incoming_messages: incoming_messages_count(range),
        conversations: conversations_active_count(range),
        ai_handle_rate: ai_handle_rate_percent(range),
        avg_response_time_seconds: avg_first_response_seconds(range),
        deposits: finance_aggregate(range, 'deposit'),
        cashouts: finance_aggregate(range, 'cashout')
      }
    end

    def growth_payload
      cur = this_week_range
      prev = previous_week_range
      keys = %i[
        incoming_messages
        conversations
        ai_handle_rate
        avg_response_time_seconds
        deposits_count
        deposits_total
        cashouts_count
        cashouts_total
      ]
      keys.index_with do |key|
        growth_pct(week_metric(cur, key), week_metric(prev, key))
      end
    end

    def week_metric(range, key)
      case key
      when :incoming_messages then incoming_messages_count(range)
      when :conversations then conversations_active_count(range)
      when :ai_handle_rate then ai_handle_rate_percent(range)
      when :avg_response_time_seconds then avg_first_response_seconds(range)
      when :deposits_count then finance_aggregate(range, 'deposit')[:count]
      when :deposits_total then finance_aggregate(range, 'deposit')[:total]
      when :cashouts_count then finance_aggregate(range, 'cashout')[:count]
      when :cashouts_total then finance_aggregate(range, 'cashout')[:total]
      else 0
      end
    end

    def growth_pct(current, previous)
      return 0.0 if previous.blank? || previous.to_f.zero?

      (((current.to_f - previous.to_f) / previous.to_f) * 100).round(1)
    end

    def players_payload
      week = this_week_range
      {
        total: @account.contacts.where(blocked: false).count,
        new_this_week: @account.contacts.where(blocked: false, created_at: week).count,
        vip: @account.contacts.where(blocked: false).where("(custom_attributes->>'loyalty_tier') = ?", 'vip').count,
        dormant: dormant_players_count,
        active_now: active_players_count
      }
    end

    def dormant_players_count
      threshold = 7.days.ago
      @account.contacts.where(blocked: false).where(
        'contacts.last_activity_at < ? OR contacts.last_activity_at IS NULL',
        threshold
      ).count
    end

    def active_players_count
      Message.unscoped.where(
        account_id: @account.id,
        message_type: :incoming,
        private: false,
        sender_type: 'Contact'
      ).where('messages.created_at > ?', 5.minutes.ago).distinct.count(:sender_id)
    end

    def ai_performance_payload(range)
      conv_ids = ai_conversation_ids(range)
      return empty_ai_performance if conv_ids.empty?

      escalated = Conversation.where(id: conv_ids).where("COALESCE(cached_label_list, '') LIKE ?", '%needs-human%').count
      total_ai = conv_ids.size
      msg_counts = Message.unscoped.where(conversation_id: conv_ids).group(:conversation_id).count
      avg_msgs = (msg_counts.values.sum.to_f / msg_counts.size).round(1)

      {
        avg_messages_per_ai_conversation: avg_msgs,
        escalation_rate_percent: ((escalated.to_f / total_ai) * 100).round(1),
        top_questions: top_ai_handled_questions(range, conv_ids)
      }
    end

    def empty_ai_performance
      {
        avg_messages_per_ai_conversation: 0.0,
        escalation_rate_percent: 0.0,
        top_questions: []
      }
    end

    def ai_conversation_ids(range)
      Message.unscoped.where(
        account_id: @account.id,
        message_type: :outgoing,
        source_id: AI_SOURCE_ID,
        created_at: range
      ).distinct.pluck(:conversation_id)
    end

    def top_ai_handled_questions(range, conv_ids)
      handled = Conversation.where(id: conv_ids).where("COALESCE(cached_label_list, '') NOT LIKE ?", '%needs-human%')
      handled_ids = handled.pluck(:id)
      return [] if handled_ids.empty?

      texts = Message.unscoped.where(
        account_id: @account.id,
        conversation_id: handled_ids,
        message_type: :incoming,
        private: false,
        created_at: range
      ).where.not(content: [nil, '']).pluck(:content)

      texts.map { |c| c.to_s.strip.truncate(80, omission: '...') }
           .reject(&:blank?)
           .tally
           .sort_by { |_text, n| -n }
           .first(5)
           .map { |text, count| { text: text, count: count } }
    end

    def incoming_messages_count(range)
      Message.unscoped.where(
        account_id: @account.id,
        message_type: :incoming,
        private: false,
        created_at: range
      ).count
    end

    def conversations_active_count(range)
      from_messages = Message.unscoped.where(account_id: @account.id, created_at: range).distinct.pluck(:conversation_id)
      from_created = @account.conversations.where(created_at: range).pluck(:id)
      (from_messages + from_created).uniq.size
    end

    def ai_handle_rate_percent(range)
      conv_with_incoming = Message.unscoped.where(
        account_id: @account.id,
        message_type: :incoming,
        private: false,
        created_at: range
      ).distinct.pluck(:conversation_id)
      return 0.0 if conv_with_incoming.empty?

      no_escalation_ids = Conversation.where(id: conv_with_incoming).where(
        "COALESCE(cached_label_list, '') NOT LIKE ?",
        '%needs-human%'
      ).pluck(:id)

      ai_handled_count = Message.unscoped.where(
        account_id: @account.id,
        message_type: :outgoing,
        source_id: AI_SOURCE_ID,
        created_at: range,
        conversation_id: no_escalation_ids
      ).distinct.count(:conversation_id)

      ((ai_handled_count.to_f / conv_with_incoming.size) * 100).round(1)
    end

    def avg_first_response_seconds(range)
      avg = ReportingEvent.where(account_id: @account.id, name: 'first_response', created_at: range).average(:value)
      avg&.to_f&.round(1) || 0.0
    end

    def finance_aggregate(range, kind)
      count = 0
      total = 0.0
      finance_entries.each do |entry|
        next unless entry[:kind].to_s == kind

        logged = parse_time(entry[:logged_at])
        next if logged.blank? || !range.cover?(logged)

        count += 1
        total += entry[:amount].to_f
      end
      { count: count, total: total.round(2) }
    end

    def finance_entries
      @finance_entries ||= begin
        rows = []
        @account.contacts.where("custom_attributes ? :k", k: FINANCE_LOG_KEY).find_each do |c|
          Array.wrap(c.custom_attributes[FINANCE_LOG_KEY]).each do |raw|
            h = raw.is_a?(Hash) ? raw.stringify_keys : {}
            rows << {
              kind: h['kind'],
              amount: h['amount'],
              logged_at: h['logged_at']
            }
          end
        end
        rows
      end
    end

    def parse_time(value)
      return if value.blank?

      @tz.parse(value.to_s)
    rescue ArgumentError, TypeError
      nil
    end

    def today_range
      @today_range ||= @now.beginning_of_day..@now.end_of_day
    end

    def this_week_range
      @this_week_range ||= (@now - 6.days).beginning_of_day..@now.end_of_day
    end

    def previous_week_range
      week_start = this_week_range.begin
      prev_end = week_start - 1.second
      (prev_end - 6.days).beginning_of_day..prev_end.end_of_day
    end
  end
end
