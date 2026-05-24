# frozen_string_literal: true

module Ai
  class TagSuggester
    def self.suggest(conversation)
      messages = conversation.messages.chat.last(20).map(&:content).join("\n")
      result = Ai::CopilotService.call_ai("Suggest 3 tags for this conversation as comma-separated hashtags:\n\n#{messages}")
      result.split(',').map { |t| t.strip.delete_prefix('#') }.reject(&:blank?).first(3)
    end
  end
end
