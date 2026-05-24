# frozen_string_literal: true

module Ai
  class KnowledgeDrafter
    def self.draft_from_conversations(account)
      resolved = account.conversations.resolved.last(20)
      snippets = resolved.flat_map { |c| c.messages.chat.last(5).map(&:content) }.join("\n---\n")
      Ai::CopilotService.call_ai("Generate an FAQ article from these resolved conversations:\n\n#{snippets}")
    end

    def self.improve(content)
      Ai::CopilotService.call_ai("Rewrite this help article for clarity:\n\n#{content}")
    end
  end
end
