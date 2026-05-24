# frozen_string_literal: true

module Contacts
  class DepositCounter
    def self.record_load!(contact:, amount:)
      return unless contact

      attrs = (contact.custom_attributes || {}).stringify_keys
      attrs['total_deposits_count'] = attrs['total_deposits_count'].to_i + 1
      attrs['total_deposits_amount'] = attrs['total_deposits_amount'].to_f + amount.to_f
      attrs['total_deposits'] = attrs['total_deposits_amount']
      attrs['deposit_count'] = attrs['total_deposits_count']
      attrs['last_deposit_amount'] = amount.to_f
      attrs['last_deposit_date'] = Time.current.iso8601
      contact.update!(custom_attributes: attrs)
    end

    def self.record_cashout!(contact:, amount:)
      return unless contact

      attrs = (contact.custom_attributes || {}).stringify_keys
      attrs['total_cashouts_count'] = attrs['total_cashouts_count'].to_i + 1
      attrs['total_cashouts_amount'] = attrs['total_cashouts_amount'].to_f + amount.to_f
      attrs['total_cashouts'] = attrs['total_cashouts_amount']
      attrs['last_cashout_date'] = Time.current.iso8601
      contact.update!(custom_attributes: attrs)
    end
  end
end
