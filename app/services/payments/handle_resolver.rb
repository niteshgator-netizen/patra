# frozen_string_literal: true

module Payments
  class HandleResolver
    MIN_WORD_LENGTH = 2
    EXACT_HANDLE_SCORE = 100
    HANDLE_NO_PREFIX_SCORE = 80
    FULL_NAME_SCORE = 60
    PER_NAME_WORD_SCORE = 30
    MIN_WINNING_SCORE = 30

    def initialize(account:, ocr_result:)
      @account = account
      @ocr = (ocr_result || {}).transform_keys(&:to_s)
    end

    # Returns { handle: PaymentHandle, score: Integer, source: 'handle'|'name'|'partial' } or nil
    def resolve
      return nil if @account.blank?

      ocr_tokens = tokenize(collected_text)
      return nil if ocr_tokens.empty?

      best = nil
      @account.payment_handles.where(status: 'active').find_each do |ph|
        score, source = score_handle(ph, ocr_tokens)
        next if score < MIN_WINNING_SCORE

        best = { handle: ph, score: score, source: source } if best.nil? || score > best[:score]
      end
      best
    rescue StandardError => e
      Rails.logger.warn("[HandleResolver] #{e.class}: #{e.message}")
      nil
    end

    private

    def collected_text
      [
        @ocr['recipient_name'], @ocr['recipient_handle'],
        @ocr['sender_name'], @ocr['sender_handle'],
        @ocr['note_or_memo'], @ocr['raw_text']
      ].compact.map(&:to_s).join(' ').downcase
    end

    # Tokenize text. Preserves $handle / @handle patterns as single tokens
    # AND extracts the word-only words separately. Returns lowercase unique tokens.
    def tokenize(text)
      return [] if text.blank?

      tokens = []
      text.scan(/[\$@][a-z0-9_.\-]+/i) { |h| tokens << h.downcase }
      remaining = text.gsub(/[\$@][a-z0-9_.\-]+/i, ' ')
      remaining.split(/[^a-z0-9]+/i).each do |w|
        wl = w.to_s.downcase
        tokens << wl if wl.length >= MIN_WORD_LENGTH
      end
      tokens.uniq
    end

    def score_handle(ph, ocr_tokens)
      score = 0
      source = nil

      normalized = ph.normalized_handle.to_s.downcase
      raw = ph.handle.to_s.downcase

      if normalized.present?
        if ocr_tokens.include?(raw) ||
           ocr_tokens.include?("$#{normalized}") ||
           ocr_tokens.include?("@#{normalized}")
          score += EXACT_HANDLE_SCORE
          source = 'handle'
        elsif ocr_tokens.include?(normalized)
          score += HANDLE_NO_PREFIX_SCORE
          source = 'handle'
        end
      end

      display = ph.try(:display_name).to_s.downcase
      if display.present?
        name_words = display.split(/[^a-z0-9]+/).reject { |w| w.length < MIN_WORD_LENGTH }
        if name_words.any?
          matched = name_words & ocr_tokens
          if matched.length == name_words.length
            score += FULL_NAME_SCORE
            source ||= 'name'
          elsif matched.any?
            score += PER_NAME_WORD_SCORE * matched.length
            source ||= 'partial'
          end
        end
      end

      [score, source]
    end
  end
end
