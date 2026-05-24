# frozen_string_literal: true

module Automation
  class ResumeFlowJob < ApplicationJob
    queue_as :low
    retry_on StandardError, wait: :polynomially_longer, attempts: 3

    def perform(run_id:, step_id:)
      run = AutomationFlowRun.find_by(id: run_id, status: 'paused')
      return unless run

      run.update!(status: 'running')
      flow = run.automation_flow
      Automation::FlowExecutor.new(
        flow: flow,
        conversation: run.conversation,
        contact: run.contact
      ).perform(start_step_id: step_id, existing_run: run)
    rescue StandardError => e
      Audit::Logger.log(action: 'job_failed', target: run, metadata: { job: self.class.name, error: e.message }) if defined?(Audit::Logger)
      raise
    end
  end
end
