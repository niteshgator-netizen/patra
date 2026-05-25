# frozen_string_literal: true

module Payments
  class GhostPaymentIngestionService
    def initialize(payment_handle:)
      @handle = payment_handle
      @account = payment_handle.account
    end

    def ingest!
      return unless @handle.verification_email.present?
      return if @handle.verification_email_password.blank?

      store = GhostPaymentStore.new(account: @account)
      emails = ImapVerifier.new(payment_handle: @handle).fetch_recent_emails(count: 20)

      emails.each do |email|
        message_id = email.message_id.to_s.presence
        next if message_id.present? && store.message_id_seen?(message_id)

        parsed = PaymentNotificationEmailParser.new(mail: email, platform: @handle.platform).parse
        next if parsed.blank?

        ghost = build_ghost_hash(parsed)
        next unless store.append!(ghost)

        Rails.logger.info(
          "[Ghost] ingested platform=#{@handle.platform} amount=#{ghost['amount']} " \
          "sender=#{ghost['sender_name']} msgid=#{ghost['message_id']}"
        )
      end

      store.archive_expired!
    rescue StandardError => e
      Rails.logger.error(
        "[GhostPaymentIngestionService] handle=#{@handle.id} failed: #{e.class}: #{e.message}"
      )
    end

    private

    def build_ghost_hash(parsed)
      now = Time.current.iso8601
      {
        'id' => SecureRandom.uuid,
        'message_id' => parsed[:message_id],
        'platform' => @handle.platform,
        'payment_handle_id' => @handle.id,
        'amount' => parsed[:amount],
        'sender_name' => parsed[:sender_name],
        'sender_handle' => parsed[:sender_handle],
        'note' => parsed[:note],
        'transaction_id' => parsed[:transaction_id],
        'email_received_at' => parsed[:email_received_at] || now,
        'ingested_at' => now,
        'status' => 'unclaimed',
        'claimed_by_contact_id' => nil,
        'claimed_at' => nil,
        'source' => 'email_ghost'
      }
    end
  end
end
