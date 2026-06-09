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
      subj = subject_clean
      body = mail_body
      has_phrase = subj.match?(PAYMENT_SUBJECT_PATTERN) || body.match?(PAYMENT_SUBJECT_PATTERN)
      return false unless has_phrase

      # A clean payment-verb SUBJECT is trusted on its own. Real provider emails are
      # FORWARDED into a gmail inbox, so the outer FROM is the forwarder, not the
      # provider — requiring a provider FROM here would reject the real payments.
      return true if subj.match?(PAYMENT_SUBJECT_PATTERN)

      # Body-only phrase (subject had no payment verb): only trust it if the email is
      # actually from / signed by a real payment provider. Kills marketing mail that
      # merely mentions a dollar amount.
      from_is_payment_source?
    end

    def platform_parse(_text)
      amount = extract_amount
      return nil if amount.nil?

      base_result(amount: amount, sender_name: extract_name, note: extract_note(combined_text))
    end

    # ── name + amount extraction (subject-first, tight capture) ────────────────
    # Names: 1-4 words, each starting with a letter; letters/space/'/-/. only.
    # No digits, no "$", no multi-line garbage — so titleize can never receive junk.
    NAME_LAZY   = "([A-Za-z][A-Za-z.'\-]*(?:[ \t]+[A-Za-z][A-Za-z.'\-]*){0,3}?)"
    NAME_GREEDY = "([A-Za-z][A-Za-z.'\-]*(?:[ \t]+[A-Za-z][A-Za-z.'\-]*){0,3})"
    NAME_STOPWORDS = %w[you your the a an our us this that money payment funds account
                        cash chime venmo paypal cashapp zelle someone customer support].freeze

    def name_patterns
      [
        /#{NAME_LAZY}\s+(?:just\s+)?(?:sent|paid)\s+you/i,
        /(?:received|payment of|sent|got)\s+\$?\s*\d[\d.]*\s+from\s+#{NAME_GREEDY}/i,
        /\bfrom\s+#{NAME_GREEDY}(?=\s*(?:\n|\z|[.,!]))/i
      ]
    end

    def extract_amount
      [subject_clean, mail_body].each do |src|
        if (m = src.match(/\$\s*(\d+(?:\.\d{1,2})?)/))
          return m[1]
        end
      end
      nil
    end

    def extract_name
      [subject_clean, mail_body].each do |src|
        name_patterns.each do |re|
          next unless (m = src.match(re))

          name = clean_name(m[1])
          return name if plausible_name?(name)
        end
      end
      nil
    end

    def clean_name(raw)
      raw.to_s.gsub(/\s+/, ' ').strip.sub(/\A[^A-Za-z]+/, '').sub(/[^A-Za-z]+\z/, '')
    end

    def plausible_name?(name)
      return false if name.blank?
      return false unless name.length.between?(2, 40)
      return false if name.match?(/[0-9$]/)

      first = name.split.first.to_s.downcase
      return false if NAME_STOPWORDS.include?(first)
      return false if NAME_STOPWORDS.include?(name.downcase)

      true
    end

    # ── sender-domain allowlist (forwarding-aware) ─────────────────────────────
    PAYMENT_DOMAINS = {
      'cashapp' => %w[cash.app square.com squareup.com],
      'chime'   => %w[chime.com],
      'venmo'   => %w[venmo.com],
      'paypal'  => %w[paypal.com],
      'zelle'   => %w[zellepay.com zelle.com]
    }.freeze

    def from_is_payment_source?
      domains = PAYMENT_DOMAINS[@platform] || []
      return true if from_addresses.any? { |addr| domains.any? { |d| addr.include?(d) } }

      # Forwarded mail: the provider domain shows up in the quoted body/headers instead.
      # Zelle is bank-forwarded, so accept the literal word "zelle" as its signature.
      signatures = domains.dup
      signatures << 'zelle' if @platform == 'zelle'
      haystack = "#{subject_clean}\n#{mail_body}".downcase
      signatures.any? { |s| haystack.include?(s) }
    end

    def from_addresses
      Array(@mail.from).map { |a| a.to_s.downcase }
    rescue StandardError
      []
    end

    def subject_clean
      s = @mail.subject.to_s
      s = s.sub(/\A\s*(?:fwd?|re)\s*:\s*/i, '') while s.match?(/\A\s*(?:fwd?|re)\s*:/i)
      s.strip
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
      [subject_clean, mail_body].join("\n")
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
