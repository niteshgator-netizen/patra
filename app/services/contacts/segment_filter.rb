# frozen_string_literal: true

module Contacts
  class SegmentFilter
    def initialize(account, filter = {})
      @account = account
      @filter = filter || {}
    end

    def contacts
      scope = @account.contacts
      scope = scope.where('name ILIKE ?', "%#{@filter['name']}%") if @filter['name'].present?
      scope = scope.where('email ILIKE ?', "%#{@filter['email']}%") if @filter['email'].present?
      scope = scope.where('phone_number ILIKE ?', "%#{@filter['phone']}%") if @filter['phone'].present?

      if @filter['tags'].present?
        tag_ids = @account.labels.where(title: Array(@filter['tags'])).pluck(:id)
        scope = scope.tagged_with(tag_ids, any: true) if tag_ids.any?
      end

      if @filter['custom_attributes'].present?
        @filter['custom_attributes'].each do |key, value|
          scope = scope.where("custom_attributes ->> ? = ?", key.to_s, value.to_s)
        end
      end

      scope
    end

    def count
      contacts.count
    end
  end
end
