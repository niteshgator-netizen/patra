# frozen_string_literal: true

module Automation
  class FlowPreview
    def initialize(flow:, contact:, conversation: nil)
      @flow = flow
      @contact = contact
      @conversation = conversation
    end

    def perform
      Automation::FlowExecutor.new(
        flow: @flow,
        conversation: @conversation,
        contact: @contact,
        preview_mode: true
      ).perform
    end
  end
end
