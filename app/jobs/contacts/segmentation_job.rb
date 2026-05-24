# frozen_string_literal: true

module Contacts
  class SegmentationJob < ApplicationJob
    queue_as :low

    def perform
      Account.find_each do |account|
        account.contacts.find_each do |contact|
          Contacts::SegmentationService.apply!(contact)
        end
      end
    end
  end
end
