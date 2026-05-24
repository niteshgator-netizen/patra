# frozen_string_literal: true

module Contacts
  class ActivityScoreJob < ApplicationJob
    queue_as :low

    def perform
      Account.find_each do |account|
        Contacts::ActivityScorer.update_all(account)
      end
    end
  end
end
