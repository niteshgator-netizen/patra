# frozen_string_literal: true

# ADM2: per-account lifecycle & control panel.
# Read panel = super-admin only (inherited devise gate).
# MUTATIONS (suspend / reactivate / toggle_feature) additionally require the
# PATRA_ADMIN_CONSOLE_ACTIONS kill-switch (default OFF — Patra::AdminConsole),
# a non-blank reason, a confirm dialog in the view, and an ADM5 audit row
# written BEFORE the change. Everything here is reversible — there is no
# delete path in this controller on purpose.
class SuperAdmin::PatraAccountsController < SuperAdmin::ApplicationController
  # patra-fix2 G2: shared kill-switch gate (redirect back + styled flash).
  include SuperAdmin::ConsoleActionsGate

  before_action :set_account
  before_action :require_console_actions!, only: [:suspend, :reactivate, :toggle_feature]
  before_action :require_reason!, only: [:suspend, :reactivate, :toggle_feature]

  def show
    range = 30.days.ago.beginning_of_day..Time.zone.now.end_of_day
    @money = Patra::FinanceAnalytics.account_scan(account_id: @account.id, range: range)
    @counts = {
      players: @account.contacts.count,
      agents: @account.account_users.count,
      conversations: @account.conversations.count
    }
    @agent_games = @account.agent_games.includes(:game).to_a
    @integration_health = @agent_games.group_by { |ag| Patra::GameHealthQuery.health_status(ag) }
                                      .transform_values(&:size)
    @last_active_at = Message.unscoped.where(account_id: @account.id).maximum(:created_at)
    @features = @account.all_features
    @recent_audits = PatraAdminAuditLog.where(target_type: 'Account', target_id: @account.id)
                                       .newest_first.limit(10)
  end

  # Suspension enforcement itself already exists (EnsureCurrentAccountHelper
  # blocks non-active accounts at the API base — verified, see ADM7 in
  # PATRA_FEAT_LOG.md). This action only flips the verified enum.
  def suspend
    if @account.suspended?
      return redirect_to super_admin_patra_account_path(@account), notice: 'Account is already suspended.'
    end

    audit!('account.suspend', metadata: { from_status: @account.status })
    @account.suspended!
    redirect_to super_admin_patra_account_path(@account), notice: 'Account suspended. Existing sessions are blocked on their next API request.'
  end

  def reactivate
    if @account.active?
      return redirect_to super_admin_patra_account_path(@account), notice: 'Account is already active.'
    end

    audit!('account.reactivate', metadata: { from_status: @account.status })
    @account.active!
    redirect_to super_admin_patra_account_path(@account), notice: 'Account reactivated.'
  end

  def toggle_feature
    feature = params[:feature].to_s
    unless valid_feature?(feature)
      return redirect_to super_admin_patra_account_path(@account), alert: 'Unknown feature flag.'
    end

    currently_on = @account.feature_enabled?(feature)
    audit!('account.feature_toggle', metadata: { feature: feature, from: currently_on, to: !currently_on })
    currently_on ? @account.disable_features!(feature) : @account.enable_features!(feature)
    redirect_to super_admin_patra_account_path(@account),
                notice: "Feature '#{feature}' #{currently_on ? 'disabled' : 'enabled'} for #{@account.name}."
  end

  private

  def set_account
    @account = Account.find(params[:id])
  end

  def require_reason!
    return if params[:reason].to_s.strip.present?

    redirect_to super_admin_patra_account_path(@account), alert: 'A reason is required for this action.'
  end

  def valid_feature?(name)
    Featurable::FEATURE_LIST.any? { |f| f['name'] == name }
  end

  def audit!(action, metadata: {})
    Patra::AdminAudit.record(
      admin: current_super_admin,
      action: action,
      target: @account,
      reason: params[:reason].to_s.strip,
      metadata: metadata,
      request: request
    )
  end
end
