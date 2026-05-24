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
        end
      end
    end
  end
end
