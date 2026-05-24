# frozen_string_literal: true

module Automation
  class FlowTemplates
    TEMPLATES = {
      'welcome_new_customer' => {
        name: 'Welcome New Customer',
        description: 'Send welcome message, wait, ask preference, and tag',
        trigger_type: 'contact_created',
        trigger_config: {},
        steps: [
          { id: 's1', type: 'send_message', config: { message: 'Welcome {{contact_name}}! Thanks for reaching out.' }, next_step_id: 's2' },
          { id: 's2', type: 'wait', config: { duration_minutes: 60 }, next_step_id: 's3' },
          { id: 's3', type: 'send_message', config: { message: 'What game would you like to play today?' }, next_step_id: 's4' },
          { id: 's4', type: 'add_tag', config: { tag: 'new-customer' }, next_step_id: nil }
        ]
      },
      'reengage_dormant' => {
        name: 'Re-engage Dormant',
        description: 'Daily schedule for contacts inactive 7+ days',
        trigger_type: 'schedule',
        trigger_config: { cron: '0 10 * * *', inactive_days: 7 },
        steps: [
          { id: 's1', type: 'condition', config: { field: 'last_active_days', operator: 'gt', value: 7 }, true_step_id: 's2', false_step_id: nil },
          { id: 's2', type: 'send_message', config: { message: 'Hey {{first_name}}, we miss you! Ready to load up again?' }, next_step_id: nil }
        ]
      },
      'cashout_approval' => {
        name: 'Cashout Approval',
        description: 'Keyword cashout triggers approval workflow',
        trigger_type: 'keyword_match',
        trigger_config: { keywords: %w[cashout withdraw] },
        steps: [
          { id: 's1', type: 'condition', config: { field: 'cashout_amount', operator: 'gt', value: 500 }, true_step_id: 's2', false_step_id: 's3' },
          { id: 's2', type: 'notify', config: { message: 'Cashout approval needed for {{contact_name}}' }, next_step_id: 's3' },
          { id: 's3', type: 'send_message', config: { message: 'Your cashout request is being processed.' }, next_step_id: nil }
        ]
      },
      'vip_auto_route' => {
        name: 'VIP Auto-Route',
        description: 'Route VIP customers to senior team',
        trigger_type: 'message_received',
        trigger_config: {},
        steps: [
          { id: 's1', type: 'condition', config: { field: 'loyalty_tier', operator: 'equals', value: 'vip' }, true_step_id: 's2', false_step_id: nil },
          { id: 's2', type: 'assign_team', config: { team_id: nil }, next_step_id: 's3' },
          { id: 's3', type: 'add_tag', config: { tag: 'vip' }, next_step_id: nil }
        ]
      },
      'after_hours' => {
        name: 'After Hours',
        description: 'Auto-reply outside business hours',
        trigger_type: 'message_received',
        trigger_config: {},
        steps: [
          { id: 's1', type: 'condition', config: { field: 'business_hours', operator: 'equals', value: 'false' }, true_step_id: 's2', false_step_id: nil },
          { id: 's2', type: 'send_message', config: { message: 'Thanks for reaching out! We are currently closed. We will respond during business hours.' }, next_step_id: nil }
        ]
      }
    }.freeze

    def self.all
      TEMPLATES.map { |key, data| data.merge(key: key) }
    end

    def self.build(account:, template_key:, created_by_user:)
      template = TEMPLATES[template_key.to_s]
      raise ArgumentError, "Unknown template: #{template_key}" unless template

      account.automation_flows.create!(
        name: template[:name],
        description: template[:description],
        trigger_type: template[:trigger_type],
        trigger_config: template[:trigger_config],
        steps: template[:steps],
        active: false,
        created_by_user: created_by_user
      )
    end
  end
end
