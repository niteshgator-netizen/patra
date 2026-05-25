# frozen_string_literal: true

module Payments
  class PaymentNotificationEmailParser
    PAYMENT_SUBJECT_PATTERN = /you (?:received|got|were paid)|payment (?:received|from|of)|sent you|paid you/i

    def initialize(mail:, platform:)
      @mail = mail
      @platform = platform.to_s.downcase
    end

    def parse
      return nil unless payment_notification?

      parsed = platform_parse(combined_text)
      return nil if parsed.blank?
      return nil unless parsed[:amount].to_f.positive?
      return nil if parsed[:sender_name].to_s.strip.blank?

      parsed.merge(
        message_id: @mail.message_id.to_s.presence,
        email_received_at: email_received_at_iso
      )
    end

    private

    def payment_notification?
      subject = @mail.subject.to_s
      body = mail_body
      return true if subject.match?(PAYMENT_SUBJECT_PATTERN) || body.match?(PAYMENT_SUBJECT_PATTERN)
      return true if subject.match?(/\$\d/) && body.match?(/\$\d/)

      false
    end

    def platform_parse(text)
      case @platform
      when 'cashapp' then parse_cashapp(text)
      when 'chime' then parse_chime(text)
      when 'venmo' then parse_venmo(text)
      when 'paypal' then parse_paypal(text)
      when 'zelle' then parse_zelle(text)
      else parse_generic(text)
      end
    end

    def parse_cashapp(text)
      if (m = text.match(/you paid\s+(.+?)\s+\$?\s*(\d+(?:\.\d{1,2})?)/im))
        return base_result(amount: m[2], sender_name: m[1], note: extract_note(text))
      end
      if (m = text.match(/(.+?)\s+paid you\s+\$?\s*(\d+(?:\.\d{1,2})?)/im))
        return base_result(amount: m[2], sender_name: m[1])
      end

      parse_generic(text)
    end

    def parse_chime(text)
      if (m = text.match(/(.+?)\s+sent you\s+\$?\s*(\d+(?:\.\d{1,2})?)/im))
        return base_result(amount: m[2], sender_name: m[1], note: extract_note(text))
      end
      if (m = text.match(/received\s+\$?\s*(\d+(?:\.\d{1,2})?)\s+from\s+(.+?)(?:\n|\.|$)/im))
        return base_result(amount: m[1], sender_name: m[2], note: extract_note(text))
      end

      parse_generic(text)
    end

    def parse_venmo(text)
      if (m = text.match(/(.+?)\s+paid you\s+\$?\s*(\d+(?:\.\d{1,2})?)(?:\s+for\s+(.+?))?(?:\n|\.|$)/im))
        return base_result(amount: m[2], sender_name: m[1], note: m[3] || extract_note(text))
      end

      parse_generic(text)
    end

    def parse_paypal(text)
      if (m = text.match(/(.+?)\s+sent you\s+\$?\s*(\d+(?:\.\d{1,2})?)/im))
        return base_result(amount: m[2], sender_name: m[1], note: extract_note(text))
      end
      if (m = text.match(/payment of\s+\$?\s*(\d+(?:\.\d{1,2})?)\s+from\s+(.+?)(?:\n|\.|$)/im))
        return base_result(amount: m[1], sender_name: m[2], note: extract_note(text))
      end

      parse_generic(text)
    end

    def parse_zelle(text)
      if (m = text.match(/\$?\s*(\d+(?:\.\d{1,2})?)\s+from\s+(.+?)(?:\n|\.|$)/im))
        return base_result(amount: m[1], sender_name: m[2], note: extract_note(text))
      end

      parse_generic(text)
    end

    def parse_generic(text)
      amount = text[/\$?\s*(\d+(?:\.\d{1,2})?)/, 1]
      sender = text[/(?:from|by|sender)[:\s]+(.+?)(?:\n|\.|$)/im, 1] ||
               text[/(.+?)\s+(?:sent you|paid you)/im, 1]
      return nil if amount.blank? || sender.blank?

      base_result(amount: amount, sender_name: sender, note: extract_note(text))
    end

    def base_result(amount:, sender_name:, note: nil)
      {
        amount: amount.to_f,
        sender_name: titleize_name(sender_name),
        sender_handle: extract_sender_handle(combined_text),
        note: note.to_s.strip.presence,
        transaction_id: extract_transaction_id(combined_text)
      }
    end

    def extract_note(text)
      m = text.match(/(?:note|memo|for)[:\s]+(.+?)(?:\n|\.|$)/im) ||
          text.match(/\bpaid you\s+\$?\d+(?:\.\d{1,2})?\s+for\s+(.+?)(?:\n|\.|$)/im)
      m&.[](1)&.strip
    end

    def extract_sender_handle(text)
      m = text.match(/[@$]([a-z0-9_.-]{2,30})/i)
      m&.[](1)&.downcase
    end

    def extract_transaction_id(text)
      candidates = text.scan(/\b([#]?[A-Z0-9-]{8,})\b/i).flatten
      candidates.find { |id| id.gsub(/^#/, '').length >= 8 }
    end

    def titleize_name(raw)
      raw.to_s.gsub(/\s+/, ' ').strip.split.map(&:capitalize).join(' ')
    end

    def combined_text
      [@mail.subject.to_s, mail_body].join("\n")
    end

    def mail_body
      @mail.body.to_s
    end

    def email_received_at_iso
      raw = @mail.date
      time = if raw.is_a?(Time) || raw.is_a?(ActiveSupport::TimeWithZone)
               raw
             else
               Time.parse(raw.to_s)
             end
      time.iso8601
    rescue ArgumentError, TypeError
      Time.current.iso8601
    end
  end
end
