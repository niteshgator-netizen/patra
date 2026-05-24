# frozen_string_literal: true

module Automation
  class FlowExecutor
    MAX_STEPS = 50

    def initialize(flow:, conversation:, contact:, preview_mode: false)
      @flow = flow
      @conversation = conversation
      @contact = contact
      @preview_mode = preview_mode
      @account = flow.account
      @step_count = 0
    end

    def perform(start_step_id: nil, existing_run: nil)
      return if blocked_contact?

      @run = existing_run || AutomationFlowRun.create!(
        automation_flow: @flow,
        conversation: @conversation,
        contact: @contact,
        status: 'running',
        started_at: Time.current,
        preview_mode: @preview_mode
      )
      @flow.increment_stat!('runs') unless existing_run

      step = start_step_id ? @flow.find_step(start_step_id) : @flow.first_step
      execute_step(step) while step && @step_count < MAX_STEPS

      @run.complete! if @run.status == 'running'
    rescue StandardError => e
      @run&.append_log!(step_id: step&.dig('id'), type: 'error', message: e.message)
      @run&.complete!(status: 'failed')
      Rails.logger.error("[FlowExecutor] flow=#{@flow.id} #{e.class}: #{e.message}")
    end

    private

    def blocked_contact?
      Contacts::BlacklistChecker.blacklisted?(@contact) ||
        @contact&.custom_attributes.to_h['opted_out'] == true
    end

    def execute_step(step)
      return unless step

      @step_count += 1
      type = step['type']
      config = step['config'] || {}

      @run.append_log!(step_id: step['id'], type: type, config: config, preview: @preview_mode)

      next_id = case type
                when 'send_message', 'send_template'
                  execute_send(config)
                  step['next_step_id']
                when 'wait'
                  schedule_wait(step)
                  nil
                when 'condition'
                  evaluate_condition(config) ? step['true_step_id'] : step['false_step_id']
                when 'assign_agent'
                  execute_assign_agent(config)
                  step['next_step_id']
                when 'assign_team'
                  execute_assign_team(config)
                  step['next_step_id']
                when 'add_tag'
                  execute_add_tag(config)
                  step['next_step_id']
                when 'remove_tag'
                  execute_remove_tag(config)
                  step['next_step_id']
                when 'set_attribute'
                  execute_set_attribute(config)
                  step['next_step_id']
                when 'resolve'
                  execute_resolve unless @preview_mode
                  step['next_step_id']
                when 'notify'
                  execute_notify(config) unless @preview_mode
                  step['next_step_id']
                when 'ab_split'
                  execute_ab_split(step)
                when 'goto'
                  config['target_step_id']
                when 'http_request'
                  execute_http_request(config) unless @preview_mode
                  step['next_step_id']
                when 'transfer'
                  execute_transfer(config) unless @preview_mode
                  step['next_step_id']
                else
                  step['next_step_id']
                end

      step = next_id ? @flow.find_step(next_id) : nil
    end

    def execute_send(config)
      content = VariableResolver.resolve(config['message'] || config['template'], @contact)
      return if @preview_mode

      user = @account.account_users.first&.user
      return unless user && @conversation

      Messages::MessageBuilder.new(user, @conversation, { content: content, private: false }).perform
      UsageRecord.increment!(account: @account, metric: 'messages_sent')
    end

    def schedule_wait(step)
      duration = step.dig('config', 'duration_minutes').to_i
      Automation::ResumeFlowJob.set(wait: duration.minutes).perform_later(
        run_id: @run.id,
        step_id: step['next_step_id']
      )
      @run.update!(status: 'paused', current_step_id: step['next_step_id'])
    end

    def evaluate_condition(config)
      field = config['field']
      operator = config['operator']
      value = config['value']

      actual = case field
               when 'message_content'
                 @conversation&.messages&.incoming&.last&.content.to_s
               when 'business_hours'
                 BusinessHoursChecker.within_hours?(@account).to_s
               else
                 @contact&.custom_attributes.to_h[field].to_s
               end

      case operator
      when 'equals' then actual == value.to_s
      when 'contains' then actual.include?(value.to_s)
      when 'gt' then actual.to_f > value.to_f
      when 'lt' then actual.to_f < value.to_f
      else false
      end
    end

    def execute_assign_agent(config)
      return if @preview_mode

      agent = @account.users.find_by(id: config['agent_id'])
      @conversation&.update!(assignee: agent) if agent
    end

    def execute_assign_team(config)
      return if @preview_mode

      team = @account.teams.find_by(id: config['team_id'])
      @conversation&.update!(team: team) if team
    end

    def execute_add_tag(config)
      return if @preview_mode || @conversation.blank?

      tag = config['tag']
      @conversation.add_labels(tag) if tag.present?
    end

    def execute_remove_tag(config)
      return if @preview_mode || @conversation.blank?

      tag = config['tag']
      @conversation.remove_labels(tag) if tag.present?
    end

    def execute_set_attribute(config)
      return if @preview_mode || @contact.blank?

      attrs = @contact.custom_attributes || {}
      attrs[config['key']] = config['value']
      @contact.update!(custom_attributes: attrs)
    end

    def execute_resolve
      @conversation&.update!(status: 'resolved')
    end

    def execute_notify(config)
      message = VariableResolver.resolve(config['message'], @contact)
      Games::TelegramNotifier.notify(@account, message) if defined?(Games::TelegramNotifier)
    end

    def execute_ab_split(step)
      variants = step.dig('config', 'variants') || []
      return step['next_step_id'] if variants.empty?

      total = variants.sum { |v| v['weight'].to_i }
      roll = rand(total)
      cumulative = 0
      chosen = variants.first

      variants.each do |variant|
        cumulative += variant['weight'].to_i
        if roll < cumulative
          chosen = variant
          break
        end
      end

      @run.append_log!(step_id: step['id'], type: 'ab_split', variant_id: chosen['next_step_id'])
      chosen['next_step_id']
    end

    def execute_http_request(config)
      url = config['url']
      method = (config['method'] || 'post').downcase
      HTTParty.send(method, url, body: config['body'].to_json, headers: { 'Content-Type' => 'application/json' })
    rescue StandardError => e
      Rails.logger.error("[FlowExecutor] HTTP request failed: #{e.message}")
    end

    def execute_transfer(config)
      inbox = @account.inboxes.find_by(id: config['inbox_id'])
      @conversation&.update!(inbox: inbox) if inbox
    end
  end
end
