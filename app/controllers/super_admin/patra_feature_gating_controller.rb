# frozen_string_literal: true

# Feature Gating — one matrix of tenant-relevant feature flags × plans, plus
# per-account overrides. Plan cells edit the plan DEFINITION (patra_plans.features
# jsonb — no enforcement yet). Per-account overrides go through the EXISTING
# audited toggle path on the Account Control Panel (PatraAccountsController#toggle_feature);
# this page only links there, it never flips account flags itself.
class SuperAdmin::PatraFeatureGatingController < SuperAdmin::ApplicationController
  include SuperAdmin::PatraFeatureGatingHelper
  # patra-fix2 G2: shared kill-switch gate (redirect back + styled flash).
  include SuperAdmin::ConsoleActionsGate

  # assign_plan writes to an account row — that crosses the console's
  # account-mutation line, so it sits behind the same kill-switch as
  # suspend/impersonate. The matrix (plan definitions) stays open.
  before_action :require_console_actions!, only: [:assign_plan]

  def show
    @plans = PatraPlan.ordered.to_a
    @flags = gateable_feature_flags
    @accounts = Account.order(:name).limit(200)
  end

  def set_plan_feature
    plan = PatraPlan.find(params[:plan_id])
    feature = params[:feature].to_s
    unless gateable_feature_flags.any? { |f| f['name'] == feature }
      return redirect_to super_admin_patra_feature_gating_path, alert: 'Unknown feature flag.'
    end
    if feature == 'patra_operator_console'
      return redirect_to super_admin_patra_feature_gating_path, alert: 'Patra Operator Console is locked pending a fix.'
    end

    enabled = params[:enabled].to_s == 'true'
    Patra::AdminAudit.record(
      admin: current_super_admin, action: 'plan.feature_set', target: plan,
      reason: params[:reason].to_s.strip.presence,
      metadata: { feature: feature, from: plan.feature_enabled?(feature), to: enabled },
      request: request
    )
    plan.update!(features: plan.features.merge(feature => enabled))
    redirect_to super_admin_patra_feature_gating_path,
                notice: "'#{feature}' #{enabled ? 'added to' : 'removed from'} the #{plan.name} plan."
  end

  def assign_plan
    account = Account.find(params[:account_id])
    plan = params[:patra_plan_id].present? ? PatraPlan.find(params[:patra_plan_id]) : nil
    Patra::AdminAudit.record(
      admin: current_super_admin, action: 'account.plan_assign', target: account,
      reason: params[:reason].to_s.strip.presence,
      metadata: { from_plan_id: account.patra_plan_id, to_plan_id: plan&.id, to_plan_name: plan&.name },
      request: request
    )
    account.update!(patra_plan_id: plan&.id)
    redirect_to super_admin_patra_feature_gating_path,
                notice: plan ? "#{account.name} is now on the #{plan.name} plan." : "#{account.name} removed from its plan."
  end

end
