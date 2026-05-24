# frozen_string_literal: true

module Analytics
  class AgentPerformanceService
    def initialize(account, period: Time.current.all_day)
      @account = account
      @period = period
    end

    def call
      agents = @account.account_users.includes(:user)
      agents.map do |au|
        user = au.user
        convs = assigned_conversations(user.id)
        {
          user_id: user.id,
          name: user.name,
          conversations_handled: convs.count,
          avg_first_response_minutes: avg_first_response(convs),
          avg_resolution_minutes: avg_resolution(convs),
          satisfaction: avg_sentiment(user.id)
        }
      end.sort_by { |r| -r[:conversations_handled] }
    end

    private

    def assigned_conversations(user_id)
      @account.conversations.where(assignee_id: user_id).where(updated_at: @period)
    end

    def avg_first_response(conversations)
      times = conversations.filter_map do |conv|
        first_in = conv.messages.incoming.order(:created_at).first
        first_out = conv.messages.outgoing.where(sender_type: 'User').order(:created_at).first
        next unless first_in && first_out

        ((first_out.created_at - first_in.created_at) / 60.0).round(1)
      end
      return 0 if times.empty?

      (times.sum / times.size).round(1)
    end

    def avg_resolution(conversations)
      resolved = conversations.where(status: :resolved)
      times = resolved.filter_map do |conv|
        next unless conv.created_at

        ((conv.updated_at - conv.created_at) / 60.0).round(1)
      end
      return 0 if times.empty?

      (times.sum / times.size).round(1)
    end

    def avg_sentiment(user_id)
      msgs = Message.unscoped.where(account_id: @account.id, sender_type: 'User', sender_id: user_id)
                    .where(created_at: @period).where.not(sentiment: nil)
      scores = msgs.filter_map { |m| m.sentiment.is_a?(Hash) ? m.sentiment['score'] : nil }
      return nil if scores.empty?

      (scores.sum / scores.size).round(2)
    end
  end
end
