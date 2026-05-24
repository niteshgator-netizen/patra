# frozen_string_literal: true

module Ai
  class SummaryService
    def self.summarize(conversation)
      messages = conversation.messages.chat.last(50).map { |m| m.content }.join("\n")
      Ai::CopilotService.call_ai("Summarize this conversation in 2-3 sentences:\n\n#{messages}")
    end
  end
end
