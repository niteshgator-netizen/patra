# frozen_string_literal: true

# Distills a player's OLDER chat history into a compact, permanent memory stored
# on contact.custom_attributes['patra_player_memory']. The recent 50 messages
# stay verbatim in the live prompt (Ai::ReplyService::HISTORY_LIMIT); this folds
# the older tail into a narrative the AI can carry forever without re-reading
# thousands of messages.
#
# ADDITIVE CONTEXT ONLY. This never touches money, finance, payments, or the
# orchestrator. A bad memory = slightly-off tone, never a money error.
#
# DeepSeek-only for the summary step (mirrors Ai::DeepseekClient's
# reasoning_content -> content fallback). On ANY model failure the existing
# memory is left UNTOUCHED rather than overwritten with garbage.
module Ai
  class PlayerMemoryWriter
    MEMORY_KEY = 'patra_player_memory'
    SUMMARY_MAX_TOKENS = 700
    SUMMARY_CHARS_CAP = 4000        # keep the stored narrative bounded
    BATCH_MESSAGE_CHARS_CAP = 280   # clip each message fed to the model

    SYSTEM_PROMPT = <<~PROMPT.freeze
      You maintain a permanent CRM memory about ONE sweepstakes/gaming customer for a cashier team.
      You are given the EXISTING memory (may be empty) and a batch of that player's OLDER messages.
      INTEGRATE the new batch into the existing memory. Never drop facts already in the existing
      memory unless the new batch clearly contradicts them. Keep it factual and compact.
      Capture: who they are, communication style, attitude/temperament, and notable history
      (favorite games, payment habits, recurring requests, problems, anything a cashier should remember).
      Do NOT include money totals or balances (those are tracked elsewhere). Do NOT invent facts.
      Return STRICT JSON only, no prose, in exactly this shape:
      {"summary":"<one short paragraph>","traits":{"style":"<e.g. chatty/terse>","patience":"<e.g. high/low>","attitude":"<e.g. friendly/demanding>"}}
    PROMPT

    def initialize(contact:, now: Time.current)
      @contact = contact
      @now = now
    end

    # Fold a batch of the player's OLDEST not-yet-summarized messages into memory.
    #   messages : Array of hashes ({ 'message_type'/'role' =>, 'content' => }) or Message records.
    #   count    : how many real messages this batch represents (defaults to batch size).
    #   persist  : write back to the contact via update_columns (skipped in unit tests).
    # Returns the new (or unchanged, on model failure) memory hash.
    def fold(messages, count: nil, persist: true)
      batch = normalize_batch(messages)
      return current_memory if batch.empty?

      existing = current_memory
      model_text = summarize(existing['summary'], batch)
      return existing if model_text.blank? # model failed -> keep old memory intact

      memory = build_memory(existing, model_text, count || batch.size)
      persist_memory(memory) if persist
      memory
    end

    # PURE: merge existing memory + fresh model output into the canonical hash.
    # Never drops the old summary: if the model returns a blank summary we keep
    # what was already stored.
    def build_memory(existing, model_text, folded_count)
      parsed = parse_model_output(model_text)
      summary = parsed['summary'].to_s.strip
      summary = existing['summary'].to_s if summary.blank?
      {
        'summary' => summary[0, SUMMARY_CHARS_CAP],
        'traits' => merge_traits(existing['traits'], parsed['traits']),
        'updated_at' => @now.utc.iso8601,
        'messages_summarized' => existing['messages_summarized'].to_i + folded_count.to_i
      }
    end

    # PURE: current stored memory normalized to the canonical shape.
    def current_memory
      raw = @contact.custom_attributes.to_h.stringify_keys[MEMORY_KEY]
      base = { 'summary' => '', 'traits' => {}, 'updated_at' => nil, 'messages_summarized' => 0 }
      return base unless raw.is_a?(Hash)

      stored = raw.stringify_keys
      base.merge(
        'summary' => stored['summary'].to_s,
        'traits' => (stored['traits'].is_a?(Hash) ? stored['traits'].stringify_keys : {}),
        'updated_at' => stored['updated_at'],
        'messages_summarized' => stored['messages_summarized'].to_i
      )
    end

    private

    # PURE: keep old trait values; overwrite only with non-blank fresh ones.
    def merge_traits(old_traits, new_traits)
      merged = old_traits.is_a?(Hash) ? old_traits.stringify_keys : {}
      fresh = new_traits.is_a?(Hash) ? new_traits.stringify_keys : {}
      fresh.each { |k, v| merged[k] = v.to_s if v.to_s.strip.present? }
      merged
    end

    def normalize_batch(messages)
      Array(messages).filter_map do |m|
        type, content =
          if m.respond_to?(:message_type) && m.respond_to?(:content)
            [m.message_type, m.content]
          else
            h = m.respond_to?(:stringify_keys) ? m.stringify_keys : m
            [(h['message_type'] || h['role']), h['content']]
          end
        text = content.to_s.strip
        next if text.blank?

        { role: role_for(type), content: text[0, BATCH_MESSAGE_CHARS_CAP] }
      end
    end

    # 1 / 'outgoing' / 'assistant' => the cashier; everything else => the player.
    def role_for(type)
      s = type.to_s
      return 'assistant' if %w[1 outgoing assistant].include?(s)

      'user'
    end

    def summarize(existing_summary, batch)
      transcript = batch.map do |m|
        speaker = (m[:role] == 'assistant') ? 'CASHIER' : 'PLAYER'
        "#{speaker}: #{m[:content]}"
      end.join("\n")

      user_content = +"EXISTING MEMORY (may be empty):\n#{existing_summary.to_s.strip}\n\n"
      user_content << "NEW OLDER MESSAGES TO FOLD IN (oldest first):\n#{transcript}"

      Ai::DeepseekClient.complete(
        system_prompt: SYSTEM_PROMPT,
        user_content: user_content,
        max_tokens: SUMMARY_MAX_TOKENS,
        temperature: 0.4
      )
    rescue StandardError => e
      Rails.logger.warn("[PlayerMemoryWriter] summarize failed contact=#{contact_id}: #{e.class}: #{e.message}")
      nil
    end

    def parse_model_output(text)
      json = extract_json(text)
      parsed = json ? JSON.parse(json) : {}
      parsed.is_a?(Hash) ? parsed : {}
    rescue JSON::ParserError
      # Model returned prose, not JSON -> treat the whole thing as the summary.
      { 'summary' => text.to_s.strip }
    end

    def extract_json(text)
      s = text.to_s
      start = s.index('{')
      finish = s.rindex('}')
      return nil if start.nil? || finish.nil? || finish < start

      s[start..finish]
    end

    def persist_memory(memory)
      attrs = @contact.custom_attributes.to_h.stringify_keys.merge(MEMORY_KEY => memory)
      # update_columns mirrors Ai::ReplyService's contact write: skips callbacks so
      # we don't fire CONTACT_UPDATED events / SyncAttributes on a background fold.
      @contact.update_columns(custom_attributes: attrs, updated_at: @now)
      Rails.logger.info("[PlayerMemoryWriter] folded contact=#{contact_id} summarized=#{memory['messages_summarized']}")
      memory
    rescue StandardError => e
      Rails.logger.warn("[PlayerMemoryWriter] persist failed contact=#{contact_id}: #{e.class}: #{e.message}")
      memory
    end

    def contact_id
      @contact.respond_to?(:id) ? @contact.id : nil
    end
  end
end
