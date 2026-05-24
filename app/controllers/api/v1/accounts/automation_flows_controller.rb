# frozen_string_literal: true

class Api::V1::Accounts::AutomationFlowsController < Api::V1::Accounts::BaseController
  before_action :fetch_flow, only: [:show, :update, :destroy, :duplicate, :preview, :analytics, :activate]

  def index
    flows = Current.account.automation_flows.order(updated_at: :desc)
    render json: flows.map { |f| flow_json(f) }
  end

  def show
    render json: flow_json(@flow)
  end

  def create
    flow = Current.account.automation_flows.create!(flow_params.merge(created_by_user: current_user))
    render json: flow_json(flow), status: :created
  end

  def update
    @flow.update!(flow_params)
    render json: flow_json(@flow)
  end

  def destroy
    @flow.destroy!
    head :ok
  end

  def duplicate
    copy = Current.account.automation_flows.create!(
      @flow.attributes.except('id', 'created_at', 'updated_at').merge(
        name: "#{@flow.name} (copy)",
        active: false,
        stats: { runs: 0, completions: 0, failures: 0 },
        created_by_user: current_user
      )
    )
    render json: flow_json(copy), status: :created
  end

  def preview
    contact = Current.account.contacts.find(params[:contact_id])
    conversation = params[:conversation_id].present? ? Current.account.conversations.find(params[:conversation_id]) : nil
    Automation::FlowPreview.new(flow: @flow, contact: contact, conversation: conversation).perform
    run = @flow.automation_flow_runs.preview.order(created_at: :desc).first
    render json: { step_log: run&.step_log || [] }
  end

  def activate
    @flow.update!(active: true)
    render json: flow_json(@flow)
  end

  def analytics
    render json: {
      runs: @flow.stats['runs'],
      completion_rate: @flow.completion_rate,
      avg_completion_time: @flow.avg_completion_time,
      step_drop_off: @flow.step_drop_off,
      ab_variant_stats: @flow.ab_variant_stats
    }
  end

  def templates
    render json: Automation::FlowTemplates.all
  end

  def from_template
    flow = Automation::FlowTemplates.build(
      account: Current.account,
      template_key: params[:template_key],
      created_by_user: current_user
    )
    render json: flow_json(flow), status: :created
  end

  private

  def fetch_flow
    @flow = Current.account.automation_flows.find(params[:id])
  end

  def flow_params
    params.permit(:name, :description, :trigger_type, :active, :version, trigger_config: {}, steps: [:id, :type, :next_step_id, :true_step_id, :false_step_id, { config: {} }])
  end

  def flow_json(flow)
    last_run = flow.automation_flow_runs.order(started_at: :desc).first
    flow.as_json.merge(
      'last_run_at' => last_run&.started_at,
      'completion_rate' => flow.completion_rate
    )
  end
end
