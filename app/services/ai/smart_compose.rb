# frozen_string_literal: true

module Ai
  class SmartCompose
    def self.complete(conversation:, prefix:)
      messages = conversation.messages.chat.last(5).map(&:content).join("\n")
      Ai::CopilotService.call_ai("Complete this agent reply (return only the completion, not the prefix):\nPrefix: #{prefix}\nContext:\n#{messages}")
    end
  end
end
