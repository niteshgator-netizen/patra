# frozen_string_literal: true

class AutomationFlow < ApplicationRecord
  TRIGGER_TYPES = %w[
    message_received conversation_opened contact_created keyword_match
    schedule webhook_inbound tag_added lifecycle_changed
  ].freeze

  STEP_TYPES = %w[
    send_message send_template wait condition assign_agent assign_team
    add_tag remove_tag set_attribute http_request ai_reply transfer
    resolve notify goto ab_split
  ].freeze

  belongs_to :account
  belongs_to :created_by_user, class_name: 'User', optional: true
  has_many :automation_flow_runs, dependent: :destroy_async
  has_many :drip_campaigns, dependent: :destroy_async

  validates :name, presence: true
  validates :trigger_type, presence: true, inclusion: { in: TRIGGER_TYPES }
  validates :steps, presence: true
  validates :version, numericality: { only_integer: true, greater_than: 0 }

  scope :active, -> { where(active: true) }
  scope :for_trigger, ->(type) { active.where(trigger_type: type) }

  def increment_stat!(key)
    stats[key.to_s] = (stats[key.to_s] || 0) + 1
    save!
  end

  def first_step
    steps.find { |s| s['id'].present? } || steps.first
  end

  def find_step(step_id)
    steps.find { |s| s['id'] == step_id }
  end

  def completion_rate
    runs = stats['runs'].to_i
    return 0 if runs.zero?

    ((stats['completions'].to_f / runs) * 100).round(1)
  end

  def avg_completion_time
    completed = automation_flow_runs.where(status: 'completed').where.not(completed_at: nil)
    return 0 if completed.empty?

    durations = completed.map { |r| r.completed_at - r.started_at }
    (durations.sum / durations.size).round
  end

  def step_drop_off
    drop_off = {}
    automation_flow_runs.find_each do |run|
      log = run.step_log || []
      next if log.empty?

      last_step = log.last['step_id']
      drop_off[last_step] = (drop_off[last_step] || 0) + 1 if run.status != 'completed'
    end
    drop_off
  end

  def ab_variant_stats
    variants = {}
    automation_flow_runs.find_each do |run|
      (run.step_log || []).each do |entry|
        next unless entry['type'] == 'ab_split'

        variant = entry['variant_id']
        variants[variant] ||= { count: 0, completed: 0 }
        variants[variant][:count] += 1
        variants[variant][:completed] += 1 if run.status == 'completed'
      end
    end
    variants
  end
end
