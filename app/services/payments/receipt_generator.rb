# frozen_string_literal: true

module Payments
  class ReceiptGenerator
    def self.generate(game_action:)
      {
        transaction_id: game_action.id,
        amount: game_action.amount,
        game: game_action.game_slug,
        date: game_action.created_at.iso8601,
        agent: game_action.user&.name,
        contact: game_action.contact&.name
      }
    end

    def self.send_to_customer(game_action:)
      receipt = generate(game_action: game_action)
      conversation = game_action.contact&.conversations&.last
      return unless conversation

      user = game_action.account.account_users.first&.user
      text = "Receipt: $#{receipt[:amount]} load on #{receipt[:game]} — TXN ##{receipt[:transaction_id]}"
      Messages::MessageBuilder.new(user, conversation, { content: text, private: false }).perform
    end
  end
end
