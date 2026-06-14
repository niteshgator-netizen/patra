# frozen_string_literal: true

# Patra (SEC) — read-only agent leaderboard. Reuses Analytics::AgentPerformanceService (the same
# data already surfaced inside patra/reports) as a standalone, sortable endpoint for the team view.
# Read-access via the report policy, so a viewer with report_view can read it but cannot mutate.
class Api::V1::Accounts::Patra::LeaderboardController < Api::V1::Accounts::BaseController
  before_action :check_authorization

  def show
    rows = Analytics::AgentPerformanceService.new(Current.account, period: period).call
    render json: { period: period_label, agents: rows }
  end

  private

  def check_authorization
    authorize :report, :view?
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
