# frozen_string_literal: true

# MEGA2 P4 - executes one inbound Telegram ops-group command. Never retries:
# a money command must not silently re-fire later from a retry queue; the
# handler logs + group-replies its own failures.
module TelegramOps
  class CommandJob < ApplicationJob
    queue_as :default
    discard_on StandardError

    def perform(payload)
      TelegramOps::CommandHandler.new(payload).process
    rescue StandardError => e
      Rails.logger.error("[TelegramOps] command job failed: #{e.class}: #{e.message}")
    end
  end
end
