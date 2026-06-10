# frozen_string_literal: true

module Contacts
  class SegmentationJob < ApplicationJob
    queue_as :low

    def perform
      Account.find_each do |account|
        account.contacts.find_each do |contact|
          Contacts::SegmentationService.apply!(contact)
        rescue StandardError => e
          # One bad contact must not kill the whole sweep.
          Rails.logger.error("[SegmentationJob] contact=#{contact.id} #{e.class}: #{e.message}")
        end
      end
    end
  end
end
