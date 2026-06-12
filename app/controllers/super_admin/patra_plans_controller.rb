# frozen_string_literal: true

# Plans & Pricing — plan DEFINITIONS only. Nothing here moves money or
# enforces limits; enforcement ships later. Every mutation writes an ADM5
# audit row before the change (same contract as the rest of the console).
class SuperAdmin::PatraPlansController < SuperAdmin::ApplicationController
  # patra-fix2 G2: shared kill-switch gate (redirect back + styled flash).
  include SuperAdmin::ConsoleActionsGate

  before_action :set_plan, only: [:edit, :update, :destroy]
  # Deleting a plan is the one irreversible action here — same kill-switch as
  # the rest of the console. Create/update stay open: definitions only.
  before_action :require_console_actions!, only: [:destroy]

  def index
    @plans = PatraPlan.ordered.to_a
  end

  def new
    @plan = PatraPlan.new
  end

  def create
    @plan = PatraPlan.new(plan_params)
    if @plan.save
      audit!('plan.create', @plan, metadata: { name: @plan.name })
      redirect_to super_admin_patra_plans_path, notice: "Plan '#{@plan.name}' created. Limits are saved but not enforced yet."
    else
      flash.now[:alert] = @plan.errors.full_messages.to_sentence
      render :new, status: :unprocessable_entity
    end
  end

  def edit; end

  def update
    before = @plan.attributes.slice('name', 'price', 'currency', 'period', 'agents_limit', 'inboxes_limit', 'ai_replies_monthly_limit', 'active')
    if @plan.update(plan_params)
      audit!('plan.update', @plan, metadata: { from: before, to: plan_params.to_h })
      redirect_to super_admin_patra_plans_path, notice: "Plan '#{@plan.name}' updated."
    else
      flash.now[:alert] = @plan.errors.full_messages.to_sentence
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    assigned = @plan.accounts.count
    if assigned.positive?
      return redirect_to super_admin_patra_plans_path,
                         alert: "Can't delete '#{@plan.name}' — #{assigned} account#{'s' if assigned != 1} still on it. Move them to another plan first."
    end

    audit!('plan.destroy', @plan, metadata: { name: @plan.name })
    @plan.destroy
    redirect_to super_admin_patra_plans_path, notice: "Plan '#{@plan.name}' deleted."
  end

  private

  def set_plan
    @plan = PatraPlan.find(params[:id])
  end

  def plan_params
    params.require(:patra_plan).permit(:name, :price, :currency, :period, :agents_limit,
                                       :inboxes_limit, :ai_replies_monthly_limit, :active, :position)
  end

  def audit!(action, plan, metadata: {})
    Patra::AdminAudit.record(
      admin: current_super_admin,
      action: action,
      target: plan,
      reason: params[:reason].to_s.strip.presence,
      metadata: metadata,
      request: request
    )
  end
end
