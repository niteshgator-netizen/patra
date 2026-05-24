# frozen_string_literal: true

module Ai
  class ImageAnalyzer
    def self.analyze(blob)
      Ai::CopilotService.call_ai("Describe what this image likely shows based on filename #{blob.filename}: payment receipt, screenshot, or document. Be specific about amounts and transaction IDs if visible.")
    end
  end
end
