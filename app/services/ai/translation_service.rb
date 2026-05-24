# frozen_string_literal: true

module Ai
  class TranslationService
    def self.translate(text:, target: 'en', source: nil)
      return text if text.blank?

      prompt = source ? "Translate from #{source} to #{target}: #{text}" : "Translate to #{target}: #{text}"
      Ai::CopilotService.call_ai(prompt)
    end
  end
end
