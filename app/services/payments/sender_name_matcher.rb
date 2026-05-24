# frozen_string_literal: true

module Payments
  class SenderNameMatcher
    RECENT_EMAIL_WINDOW = 30.minutes

    def initialize(account:, sender_name:, expected_amount:)
      @account = account
      @sender_name = sender_name.to_s.strip
      @expected_amount = expected_amount.to_f
    end

    def find_match
      return nil if @account.blank? || @sender_name.blank? || @expected_amount <= 0

      @account.payment_handles.where(status: 'active').where.not(verification_email: nil).find_each do |handle|
        match = match_on_handle(handle)
        return match if match
      end

      nil
    rescue StandardError => e
      Rails.logger.error("[SenderNameMatcher] account=#{@account&.id} failed: #{e.message}")
      nil
    end

    private

    def match_on_handle(handle)
      verifier = ImapVerifier.new(payment_handle: handle)
      email = verifier.verify(
        amount: @expected_amount,
        sender_name: @sender_name,
        transaction_id: nil
      )
      return nil unless email

      sent_at = parse_email_time(email)
      return nil if sent_at && sent_at < RECENT_EMAIL_WINDOW.ago

      transaction_id = extract_transaction_id(email)
      return nil if transaction_id.present? && txn_already_loaded?(transaction_id)

      {
        payment_handle: handle,
        amount: @expected_amount,
        sender_name: @sender_name,
        transaction_id: transaction_id,
        sent_at: sent_at,
        email_subject: email.subject.to_s
      }
    rescue StandardError => e
      Rails.logger.error("[SenderNameMatcher] handle=#{handle.id} failed: #{e.message}")
      nil
    end

    def parse_email_time(email)
      raw = email.date
      return raw if raw.is_a?(Time) || raw.is_a?(ActiveSupport::TimeWithZone)

      Time.parse(raw.to_s)
    rescue ArgumentError, TypeError
      nil
    end

    def extract_transaction_id(email)
      body = email.body.to_s
      candidates = body.scan(/\b([#]?[A-Z0-9-]{8,})\b/i).flatten
      candidates.find { |id| id.gsub(/^#/, '').length >= 8 }
    end

    # Mirrors Games::ConversationOrchestrator#payment_already_loaded? — GameAction metadata lookup
    def txn_already_loaded?(transaction_id)
      GameAction
        .where(account_id: @account.id, action_type: 'load', status: 'success')
        .where('metadata::text LIKE ?', "%#{transaction_id}%")
        .exists?
    end
  end
end
