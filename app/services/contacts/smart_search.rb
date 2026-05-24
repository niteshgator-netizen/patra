# frozen_string_literal: true

module Contacts
  class SmartSearch
    def initialize(account, query)
      @account = account
      @query = query.to_s.strip
    end

    def results
      return @account.contacts.none if @query.blank?

      scope = @account.contacts
      scope.where('name ILIKE :q OR email ILIKE :q OR phone_number ILIKE :q', q: "%#{@query}%")
           .or(scope.where("custom_attributes::text ILIKE ?", "%#{@query}%"))
           .or(scope.where(id: game_username_contact_ids))
           .or(scope.where(id: message_contact_ids))
           .distinct
    end

    private

    def game_username_contact_ids
      GameAction.where(account: @account).where('game_username ILIKE ?', "%#{@query}%").pluck(:contact_id).compact
    end

    def message_contact_ids
      Message.joins(:conversation)
             .where(conversations: { account_id: @account.id })
             .where('messages.content ILIKE ?', "%#{@query}%")
             .pluck('conversations.contact_id').compact
    end
  end
end
