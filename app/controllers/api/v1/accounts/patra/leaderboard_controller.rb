# frozen_string_literal: true

# Patra (SEC) — read-only agent leaderboard. Reuses Analytics::AgentPerformanceService (the same
# data already surfaced inside patra/reports) as a standalone, sortable endpoint for the team view.
# Read-only: visible to administrators and any custom_role carrying report_view OR report_manage —
# so the Viewer tier (which holds report_view) can read it. No mutation path exists.
class Api::V1::Accounts::Patra::LeaderboardController < Api::V1::Accounts::BaseController
  before_action :check_authorization

  def show
    rows = Analytics::AgentPerformanceService.new(Current.account, period: period).call
    render json: { period: period_label, agents: rows }
  end

  private

  # NOTE: ReportPolicy#view? gates on report_manage only, which would exclude a report_view-only
  # Viewer. We authorize explicitly here so the read-only Viewer tier can see the leaderboard.
  def check_authorization
    return if Current.account_user&.administrator?
    return if (Array(Current.account_user&.custom_role&.permissions) & %w[report_view report_manage]).any?

    raise Pundit::NotAuthorizedError
  end

  def period
    case params[:period].to_s
    when 'week' then 7.days.ago.beginning_of_day..Time.current
    when 'month' then 30.days.ago.beginning_of_day..Time.current
    else Time.current.beginning_of_day..Time.current
    end
  end

  def period_label
    %w[week month].include?(params[:period].to_s) ? params[:period].to_s : 'today'
  end
end
