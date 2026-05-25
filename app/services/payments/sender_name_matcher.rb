# frozen_string_literal: true

module Payments
  class SenderNameMatcher
    RECENT_EMAIL_WINDOW = 30.minutes

    def initialize(account:, sender_name:, expected_amount:, contact: nil, note: nil)
      @account = account
      @sender_name = sender_name.to_s.strip
      @expected_amount = expected_amount.to_f
      @contact = contact
      @note = note.to_s.strip.presence
    end

    def find_match
      return nil if @account.blank? || @sender_name.blank? || @expected_amount <= 0

      ghost = scan_ghost_pool
      if ghost
        if @contact
          claimed = GhostPaymentStore.new(account: @account).claim!(ghost_id: ghost['id'], contact: @contact)
          ghost = claimed
          Rails.logger.info("[SenderNameMatcher] ghost_claimed id=#{ghost['id']} contact=#{@contact.id}")
        end
        return build_match_hash(ghost.merge('match_source' => 'ghost_pool'))
      end

      if @contact
        vault_match = scan_contact_vault
        return build_match_hash(vault_match.merge('match_source' => 'contact_vault')) if vault_match
      end

      live_imap_fallback
    rescue StandardError => e
      Rails.logger.error("[SenderNameMatcher] account=#{@account&.id} failed: #{e.message}")
      nil
    end

    private

    def scan_ghost_pool
      GhostPaymentStore.new(account: @account).find_unclaimed(within: RECENT_EMAIL_WINDOW).find do |ghost|
        amount_match?(ghost['amount']) &&
          name_match?(ghost['sender_name']) &&
          note_match?(ghost['note'])
      end
    end

    def scan_contact_vault
      logs = Array(@contact.custom_attributes&.dig('patra_finance_logs'))
      logs.reverse_each do |entry|
        next unless entry.is_a?(Hash)
        next unless entry['email_confirmed'] == true
        next if entry['flag_reason'].to_s.strip.present?

        time_str = entry['recorded_at'] || entry['image_received_at'] || entry['transaction_time']
        recorded = parse_email_time(time_str)
        next if recorded && recorded < RECENT_EMAIL_WINDOW.ago

        next unless amount_match?(entry['amount'])
        next unless name_match?(entry['sender_name'])
        next unless note_match?(entry['note_or_memo'] || entry['note'])

        transaction_id = entry['transaction_id'].to_s.presence
        next if transaction_id.present? && txn_already_loaded?(transaction_id)

        return entry.stringify_keys
      end

      nil
    end

    def live_imap_fallback
      @account.payment_handles.where(status: 'active').where.not(verification_email: nil).find_each do |handle|
        match = match_on_handle(handle)
        return build_match_hash(match.stringify_keys.merge('match_source' => 'live_imap')) if match
      end

      nil
    end

    def match_on_handle(handle)
      verifier = ImapVerifier.new(payment_handle: handle)
      email = verifier.verify(
        amount: @expected_amount,
        sender_name: @sender_name,
        transaction_id: nil
      )
      return nil unless email

      sent_at = parse_email_time(email.date)
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

    def build_match_hash(data)
      data = data.stringify_keys
      handle = data['payment_handle'].presence || PaymentHandle.find_by(id: data['payment_handle_id'])

      {
        payment_handle: handle,
        amount: data['amount'].to_f,
        sender_name: data['sender_name'].presence || @sender_name,
        transaction_id: data['transaction_id'],
        sent_at: parse_email_time(data['email_received_at'] || data['sent_at'] || data['recorded_at']),
        email_subject: data['email_subject'].to_s,
        match_source: data['match_source'],
        ghost_id: data['ghost_id'] || data['id']
      }.compact
    end

    def amount_match?(value)
      (value.to_f - @expected_amount).abs < 0.01
    end

    def name_match?(value)
      return false if value.to_s.strip.blank?

      a = @sender_name.downcase
      b = value.to_s.downcase
      a.include?(b) || b.include?(a)
    end

    def note_match?(value)
      return true if @note.blank?

      value.to_s.downcase.include?(@note.downcase)
    end

    def parse_email_time(raw)
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

    def txn_already_loaded?(transaction_id)
      GameAction
        .where(account_id: @account.id, action_type: 'load', status: 'success')
        .where('metadata::text LIKE ?', "%#{transaction_id}%")
        .exists?
    end
  end
end
