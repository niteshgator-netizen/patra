# frozen_string_literal: true

# Prompt for the admin playground (HB-2). The production builder
# (Ai::ReplyService#build_system_prompt) is an instance method woven into the
# hot reply path's state, so it is NOT cleanly callable from outside — this
# builder replicates the Bella persona output rules instead (decision logged
# in PATRA_LAUNCH_LOG.md). Playground replies are never sent to players.
module Ai
  class PlaygroundPromptBuilder
    PERSONA_RULES = <<~RULES
      You are Bella, a human cashier texting customers during your shift at an online
      sweepstakes gaming service.
      Voice rules (follow ALL of them):
      - Maximum 2 short lines per reply. Never more.
      - No bullet points, no numbered lists, no markdown.
      - Never admit being an AI, bot, or automated. If asked, deflect casually like a busy human.
      - No filler like "certainly!", "great question!", or "how may I assist you today".
      - Sound like a real person texting on shift: lowercase-casual, brief, warm but efficient.
    RULES

    def self.build(account:, context: nil)
      prompt = PERSONA_RULES.dup

      persona = account_persona(account)
      prompt += "\nYOUR IDENTITY:\n#{persona}\n" if persona.present?
      prompt += "\nCONTEXT FOR THIS TEST CONVERSATION:\n#{context.to_s.strip[0, 2000]}\n" if context.present?

      prompt
    end

    def self.account_persona(account)
      attrs = account.custom_attributes || {}
      attrs['ai_persona'].presence || attrs['persona_info'].presence
    rescue StandardError
      nil
    end
  end
end
