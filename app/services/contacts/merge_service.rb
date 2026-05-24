# frozen_string_literal: true

module Contacts
  class MergeService
    pattr_initialize [:account!, :primary_contact!, :duplicate_contact!]

    def perform!
      raise ArgumentError, 'Contacts must belong to the same account' unless same_account?

      ActiveRecord::Base.transaction do
        duplicate_contact.conversations.update_all(contact_id: primary_contact.id)
        merge_custom_attributes!
        duplicate_contact.destroy!
      end

      primary_contact.reload
    end

    private

    def same_account?
      primary_contact.account_id == duplicate_contact.account_id &&
        primary_contact.account_id == account.id
    end

    def merge_custom_attributes!
      primary = (primary_contact.custom_attributes || {}).stringify_keys
      duplicate = (duplicate_contact.custom_attributes || {}).stringify_keys

      duplicate.each do |key, value|
        next if value.blank?
        next if primary[key].present?

        primary[key] = value
      end

      primary_contact.update!(custom_attributes: primary)
    end
  end
end
