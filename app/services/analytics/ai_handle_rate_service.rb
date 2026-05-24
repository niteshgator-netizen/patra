# frozen_string_literal: true

module Analytics
  class AiHandleRateService
    def initialize(account, period: Time.current.all_day)
      @account = account
      @period = period
    end

    def call
      total = @account.conversations.where(created_at: @period).count
      return { total: 0, ai_resolved: 0, rate: 0.0 } if total.zero?

      human_conv_ids = Message.unscoped.where(account_id: @account.id, private: false)
                              .outgoing.where(created_at: @period, sender_type: 'User')
                              .distinct.pluck(:conversation_id)

      ai_with_replies = @account.conversations.where(created_at: @period)
                                .joins(:messages)
                                .where(messages: { message_type: :outgoing, sender_type: 'AgentBot' })
                                .distinct.count

      ai_resolved = @account.conversations.where(created_at: @period, status: :resolved)
                            .where.not(id: human_conv_ids).count

      {
        total: total,
        ai_conversations: ai_with_replies,
        ai_resolved: ai_resolved,
        rate: ((ai_resolved.to_f / total) * 100).round(1)
      }
    end
  end
end
