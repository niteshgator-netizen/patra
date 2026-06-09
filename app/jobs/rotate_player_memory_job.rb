# frozen_string_literal: true

# Rotation that keeps per-player AI memory + token cost bounded.
#
# The recent 50 messages stay verbatim in the live prompt. Once a player has
# accumulated >= 1000 messages that are NOT yet folded into memory, the OLDEST
# 500 of those are distilled by Ai::PlayerMemoryWriter into
# contact.custom_attributes['patra_player_memory'] and messages_summarized is
# bumped by the batch size. Recent history always stays verbatim.
#
# ADDITIVE ONLY. Reads message rows for context; never writes messages, never
# touches money / finance / payments / orchestrator. Mirrors the
# ReengageDormantContactsJob fan-out pattern (Account.find_each -> contacts).
class RotatePlayerMemoryJob < ApplicationJob
  queue_as :low

  ROTATION_TRIGGER = 1000        # un-summarized messages needed before we fold
  FOLD_BATCH = 500               # how many oldest un-summarized messages per run
  REAL_TYPES = [0, 1].freeze     # incoming + outgoing only (skip activity/template)

  # PURE decision: given the totals, should we fold and what's the new count?
  # Returns nil when below the trigger, else { batch_size:, new_summarized: }.
  def self.fold_plan(total_messages:, messages_summarized:)
    unsummarized = total_messages.to_i - messages_summarized.to_i
    return nil if unsummarized < ROTATION_TRIGGER

    { batch_size: FOLD_BATCH, new_summarized: messages_summarized.to_i + FOLD_BATCH }
  end

  def perform
    Account.find_each do |account|
      account.contacts.find_each do |contact|
        rotate_contact(account, contact)
      rescue StandardError => e
        Rails.logger.warn("[RotatePlayerMemory] contact=#{contact.id} #{e.class}: #{e.message}")
      end
    end
  end

  private

  def rotate_contact(account, contact)
    conversation_ids = contact.conversations.pluck(:id)
    return if conversation_ids.empty?

    scope = Message.where(conversation_id: conversation_ids, message_type: REAL_TYPES)
    total = scope.count
    summarized = current_summarized(contact)

    plan = self.class.fold_plan(total_messages: total, messages_summarized: summarized)
    return if plan.nil?

    # Oldest un-summarized window: skip the messages already folded, take the next batch.
    batch = scope.order(created_at: :asc, id: :asc)
                 .offset(summarized)
                 .limit(plan[:batch_size])
                 .pluck(:message_type, :content)
                 .map { |mtype, content| { 'message_type' => mtype, 'content' => content } }
    return if batch.empty?

    Ai::PlayerMemoryWriter.new(contact: contact).fold(batch, count: batch.size)
    Rails.logger.info(
      "[RotatePlayerMemory] folded contact=#{contact.id} account=#{account.id} " \
      "total=#{total} summarized #{summarized}->#{summarized + batch.size}"
    )
  end

  def current_summarized(contact)
    mem = contact.custom_attributes.to_h.stringify_keys['patra_player_memory']
    mem.is_a?(Hash) ? mem.stringify_keys['messages_summarized'].to_i : 0
  end
end
