# frozen_string_literal: true

module Contacts
  class ActivityScoreJob < ApplicationJob
    queue_as :low

    def perform
      Account.find_each do |account|
        Contacts::ActivityScorer.update_all(account)
      rescue StandardError => e
        # One bad account must not kill the whole sweep.
        Rails.logger.error("[ActivityScoreJob] account=#{account.id} #{e.class}: #{e.message}")
      end
    end
  end
end
