# frozen_string_literal: true

module Payments
  class SingleContactImapJob < ApplicationJob
    queue_as :default
    retry_on StandardError, wait: 10.seconds, attempts: 2

    def perform(contact_id, account_id)
      contact = Account.find_by(id: account_id)&.contacts&.find_by(id: contact_id)
      return unless contact

      Payments::EmailConfirmationService.new(contact: contact).check_all
      Rails.logger.info("[SingleContactImapJob] checked contact=#{contact_id}")
    ensure
      ActiveRecord::Base.connection_pool.release_connection
    end
  end
end
