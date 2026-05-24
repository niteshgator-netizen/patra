# frozen_string_literal: true

module Payments
  class ImapCheckJob < ApplicationJob
    queue_as :scheduled_jobs
    retry_on StandardError, wait: :polynomially_longer, attempts: 3

    def perform
      PaymentHandle.where.not(verification_email: nil).find_each do |handle|
        verifier = Payments::ImapVerifier.new(payment_handle: handle)
        handle.account.game_actions.where(status: 'pending_verification').find_each do |action|
          meta = action.metadata.to_h
          match = verifier.verify(
            amount: action.amount,
            sender_name: meta['sender_name'],
            transaction_id: meta['transaction_id']
          )
          action.update!(status: match ? 'success' : 'flagged') if match || meta['screenshot_sent']
        end
      end
    end
  end
end
