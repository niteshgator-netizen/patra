# frozen_string_literal: true

module Payments
  class EmailConfirmationService
    MAX_CHECK_ATTEMPTS = 24

    def initialize(contact:)
      @contact = contact
      @account = contact.account
    end

    def check_all
      logs = finance_logs
      checked = 0
      confirmed = 0
      modified = false

      logs.each do |entry|
        next unless entry.is_a?(Hash)
        next unless eligible_for_check?(entry)

        checked += 1
        before_attempts = entry['email_check_attempts'].to_i
        before_confirmed = entry['email_confirmed']

        if check_entry(entry)
          confirmed += 1
        end

        modified = true if entry['email_confirmed'] != before_confirmed ||
                         entry['email_check_attempts'].to_i != before_attempts
      end

      persist_logs!(logs) if modified

      { checked: checked, confirmed: confirmed }
    end

    def check_entry(entry)
      return true if entry['email_confirmed'] == true && entry['email_subject'].present?
      return false unless entry.is_a?(Hash)
      return false unless eligible_for_check?(entry)

      handle = resolve_payment_handle(entry)
      return false unless handle

      match = verify_with_imap(handle, entry)
      if match
        entry['email_confirmed'] = true
        entry['email_confirmed_at'] = Time.current.iso8601
        entry['email_match_source'] = 'imap_poll'
        entry['status_before_email_verify'] = entry['status']
        entry['status'] = 'Email Verified'

        # Extract and store email content for ledger display
        begin
          entry['email_subject'] = match.subject.to_s.encode('UTF-8', invalid: :replace, undef: :replace)[0, 200]
          entry['email_from'] = match.from&.first.to_s[0, 100]
          entry['email_date'] = match.date&.iso8601 rescue match.date.to_s
          entry['email_body_snippet'] = match.body.to_s.encode('UTF-8', invalid: :replace, undef: :replace)[0, 500]

          # Extract amount from email body/subject
          email_text = "#{match.subject} #{match.body}".to_s
          amount_match = email_text.match(/\$[\d,]+\.?\d{0,2}/)
          entry['email_amount'] = amount_match[0].gsub(/[$,]/, '').to_f if amount_match

          # Extract sender name from email subject
          subject = match.subject.to_s
          name_match = subject.match(/^(.+?)(?:\s+(?:sent|paid|just sent))/i)
          entry['email_sender_name'] = name_match[1].strip if name_match
          # Fallback: if sender is generic ("You", "alerts@..."), try parsing subject for real name
          if entry['email_sender_name'].blank? || entry['email_sender_name'].to_s.downcase.in?(%w[you alerts])
            subject_name = subject.match(/^(.+?)\s+(?:just\s+)?sent\s+you/i)
            entry['email_sender_name'] = subject_name[1].strip if subject_name
          end
        rescue StandardError => e
          Rails.logger.warn("[EmailConfirmationService] email data extraction failed: #{e.message}")
        end

        true
      else
        entry['email_check_attempts'] = entry['email_check_attempts'].to_i + 1
        false
      end
    end

    DEFAULT_SCORING_CONFIG = {
      'screenshot_present' => 25,
      'amount_match' => 25,
      'sender_match' => 15,
      'recipient_match' => 10,
      'txn_id_present' => 10,
      'email_confirmed' => 10,
      'note_present' => 5,
      'time_proximity' => 5,
      'time_proximity_minutes' => 30,
      'auto_load_threshold' => 80,
      'escalate_threshold' => 40,
      'decline_threshold' => 39
    }.freeze

    def self.scoring_config_for(account, platform: nil)
      return DEFAULT_SCORING_CONFIG unless account

      all_config = account.custom_attributes&.dig('payment_scoring_config') || {}
      base = DEFAULT_SCORING_CONFIG.merge(all_config['default'] || all_config.except('default', 'custom_rules') || {})
      if platform.present? && all_config[platform.to_s].is_a?(Hash)
        base = base.merge(all_config[platform.to_s])
      end
      custom_rules = all_config['custom_rules'] || []
      base['custom_rules'] = custom_rules
      base
    end

    def self.confidence_score(entry, account: nil)
      platform = entry.is_a?(Hash) ? entry['platform'].to_s.downcase : ''
      cfg = scoring_config_for(account, platform: platform)
      zero_breakdown = {
        'total' => 0,
        'screenshot' => 0,
        'amount_match' => 0,
        'sender_match' => 0,
        'recipient_match' => 0,
        'txn_id' => 0,
        'email_confirmed' => 0,
        'note_present' => 0,
        'time_proximity' => 0,
        'custom_rules' => 0
      }
      return zero_breakdown unless entry.is_a?(Hash)

      screenshot_pts = entry['image_url'].present? ? cfg['screenshot_present'].to_i : 0

      amount_pts = if entry['email_amount'].present? && entry['amount'].present? &&
                      entry['email_amount'].to_f == entry['amount'].to_f
                     cfg['amount_match'].to_i
                   else
                     0
                   end

      email_sender = entry['email_sender_name'].to_s.downcase.strip
      ocr_sender = entry['sender_name'].to_s.downcase.strip
      ocr_recipient = entry['recipient_name'].to_s.downcase.strip

      sender_pts = 0
      if email_sender.present? && ocr_sender.present?
        sender_pts = cfg['sender_match'].to_i if names_overlap?(email_sender, ocr_sender)
      elsif email_sender.present? && ocr_recipient.present?
        sender_pts = cfg['sender_match'].to_i if names_overlap?(email_sender, ocr_recipient)
      end

      # If email sender present and is the customer (not "You"), full sender points when email confirmed
      if sender_pts.zero? && entry['email_sender_name'].present?
        email_s = entry['email_sender_name'].to_s.downcase
        sender_pts = cfg['sender_match'].to_i if email_s.present? && !%w[you alerts].include?(email_s) && entry['email_confirmed']
      end

      recipient_pts = 0
      if entry['email_confirmed'] == true && email_sender.present? && ocr_recipient.present?
        recipient_pts = cfg['recipient_match'].to_i if names_overlap?(email_sender, ocr_recipient) || entry['email_amount'].present?
      end

      txn_pts = entry['transaction_id'].present? && entry['transaction_id'].to_s.length > 3 ? cfg['txn_id_present'].to_i : 0
      email_pts = entry['email_confirmed'] == true ? cfg['email_confirmed'].to_i : 0
      note_pts = entry['note_or_memo'].present? ? cfg['note_present'].to_i : 0

      time_pts = 0
      if entry['image_received_at'].present? && entry['email_date'].present?
        begin
          img_time = Time.parse(entry['image_received_at'].to_s)
          email_time = Time.parse(entry['email_date'].to_s)
          window_seconds = cfg['time_proximity_minutes'].to_i * 60
          window_seconds = 1800 if window_seconds <= 0
          time_pts = cfg['time_proximity'].to_i if (img_time - email_time).abs < window_seconds
        rescue StandardError
          # skip
        end
      end

      custom_pts = 0
      Array(cfg['custom_rules']).each do |rule|
        next unless rule.is_a?(Hash) && rule['name'].present?

        custom_pts += rule['points'].to_i
      end

      score = screenshot_pts + amount_pts + sender_pts + recipient_pts + txn_pts + email_pts + note_pts + time_pts + custom_pts

      {
        'total' => score.clamp(0, 100),
        'screenshot' => screenshot_pts,
        'amount_match' => amount_pts,
        'sender_match' => sender_pts,
        'recipient_match' => recipient_pts,
        'txn_id' => txn_pts,
        'email_confirmed' => email_pts,
        'note_present' => note_pts,
        'time_proximity' => time_pts,
        'custom_rules' => custom_pts,
        'auto_load_threshold' => cfg['auto_load_threshold'].to_i,
        'escalate_threshold' => cfg['escalate_threshold'].to_i,
        'decline_threshold' => cfg['decline_threshold'].to_i
      }
    end

    def self.names_overlap?(a, b)
      return false if a.blank? || b.blank?

      a_first = a.to_s.downcase.split(/\s+/).first
      b_first = b.to_s.downcase.split(/\s+/).first
      return true if a_first.present? && b.include?(a_first)
      return true if b_first.present? && a.include?(b_first)

      false
    end

    private_class_method :names_overlap?

    private

    def finance_logs
      Array(@contact.custom_attributes&.dig('patra_finance_logs')).map do |raw|
        raw.is_a?(Hash) ? raw.stringify_keys : raw
      end
    end

    def persist_logs!(logs)
      attrs = (@contact.custom_attributes || {}).stringify_keys
      attrs['patra_finance_logs'] = logs
      @contact.custom_attributes = attrs
      @contact.save!(touch: false)
    end

    def eligible_for_check?(entry)
      return false if entry['email_confirmed'] == true && entry['email_subject'].present?
      return false unless StatusNormalizer.needs_email_confirmation?(entry['raw_status'])
      return false if entry['email_check_attempts'].to_i >= MAX_CHECK_ATTEMPTS

      resolve_payment_handle(entry).present?
    end

    def resolve_payment_handle(entry)
      platform = entry['platform'].to_s.downcase
      return nil if platform.blank? || @account.blank?

      recip = entry['recipient_handle'].to_s.gsub(/^[\$@]/, '').strip.downcase
      recip = entry['resolved_handle'].to_s.gsub(/^[\$@]/, '').strip.downcase if recip.blank?
      return nil if recip.blank?

      @account.payment_handles.where(platform: platform).find do |handle|
        handle.normalized_handle == recip
      end
    end

    def verify_with_imap(handle, entry)
      verifier = ImapVerifier.new(payment_handle: handle)
      verifier.verify(
        amount: entry['amount'],
        sender_name: entry['sender_name'],
        transaction_id: entry['transaction_id']
      )
    rescue StandardError => e
      Rails.logger.error(
        "[EmailConfirmationService] IMAP verify failed contact=#{@contact.id} handle=#{handle.id}: #{e.message}"
      )
      false
    end
  end
end
