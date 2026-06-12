# frozen_string_literal: true

# patra-final 5g (G45): READ-ONLY browser for the finance entries the
# Command Center counts as malformed. No mutations — finance data is never
# touched from here; Genius decides offline what to do with the rows.
class SuperAdmin::PatraMalformedFinanceController < SuperAdmin::ApplicationController
  def show
    @rows = Patra::FinanceAnalytics.malformed_report
    @account_names = Account.where(id: @rows.map { |r| r[:account_id] }.uniq).pluck(:id, :name).to_h
  end
end
