# frozen_string_literal: true

# F15 — executes an approved cashout in the background. Safe to retry:
# AutoResume.execute! is idempotent via the appr_<id> order_id.
module Approvals
  class AutoResumeJob < ApplicationJob
    queue_as :default

    retry_on StandardError, wait: :polynomially_longer, attempts: 3 do |job, error|
      Rails.logger.error("[AutoResumeJob] GIVING UP approval=#{job.arguments.first} #{error.class}: #{error.message}")
    end

    def perform(approval_request_id)
      approval = ApprovalRequest.find_by(id: approval_request_id)
      return if approval.nil?

      Approvals::AutoResume.execute!(approval)
    end
  end
end
