# frozen_string_literal: true

module Contacts
  class LifecycleUpdateJob < ApplicationJob
    queue_as :low

    def perform
      Account.find_each do |account|
        account.contacts.find_each do |contact|
          stage = Contacts::LifecycleCalculator.calculate(contact)
          attrs = (contact.custom_attributes || {}).stringify_keys
          next if attrs['lifecycle_stage'] == stage

          attrs['lifecycle_stage'] = stage
          contact.update!(custom_attributes: attrs)
        rescue StandardError => e
          # One bad contact must not kill the whole sweep.
          Rails.logger.error("[LifecycleUpdateJob] contact=#{contact.id} #{e.class}: #{e.message}")
        end
      end
    end
  end
end
