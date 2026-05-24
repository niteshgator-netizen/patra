# frozen_string_literal: true

module Assignment
  class RoundRobinService
    pattr_initialize [:account!, :inbox!]

    def assign_conversation(conversation)
      return unless enabled?

      agent = pick_agent
      return unless agent

      conversation.update!(assignee: agent)
      send_out_of_office_reply(conversation, agent) if agent_out_of_office?(agent)
    end

    def pick_agent
      online_agents = inbox.inbox_members.includes(:user).map(&:user).select { |u| online?(u) }
      return nil if online_agents.empty?

      counts = open_conversation_counts(online_agents.map(&:id))
      max_per_agent = account_setting('round_robin_max_conversations', 50).to_i

      eligible = online_agents.reject { |u| counts[u.id].to_i >= max_per_agent }
      return nil if eligible.empty?

      eligible.min_by { |u| counts[u.id].to_i }
    end

    private

    def enabled?
      account_setting('round_robin_enabled', true)
    end

    def account_setting(key, default)
      attrs = (account.custom_attributes || {}).stringify_keys
      val = attrs[key]
      val.nil? ? default : val
    end

    def online?(user)
      account_user = account.account_users.find_by(user_id: user.id)
      account_user&.availability == 'online'
    end

    def open_conversation_counts(user_ids)
      Conversation.where(inbox_id: inbox.id, assignee_id: user_ids, status: :open)
                  .group(:assignee_id)
                  .count
    end

    def agent_out_of_office?(user)
      attrs = (user.custom_attributes || {}).stringify_keys
      attrs['out_of_office'] == true
    end

    def send_out_of_office_reply(conversation, agent)
      message = (agent.custom_attributes || {}).stringify_keys['out_of_office_message']
      message = message.presence || 'I am currently out of office. Another agent will assist you shortly.'
      Messages::MessageBuilder.new(Current.user || agent, conversation, { content: message, private: false }).perform

      next_agent = pick_agent
      conversation.update!(assignee: next_agent) if next_agent && next_agent.id != agent.id
    end
  end
end
