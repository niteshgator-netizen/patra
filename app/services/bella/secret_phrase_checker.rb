module Bella
  class SecretPhraseChecker
    Result = Struct.new(:triggered, :phrase_record, keyword_init: true)

    def initialize(account:, conversation:, message_content:)
      @account = account
      @conversation = conversation
      @content = message_content.to_s.downcase
    end

    def check_and_trigger!
      return Result.new(triggered: false) if @content.blank? || @account.nil?

      @account.secret_phrases.enabled.each do |sp|
        phrase = sp.phrase.to_s.downcase
        next if phrase.blank?

        if @content.include?(phrase)
          fire(sp)
          return Result.new(triggered: true, phrase_record: sp)
        end
      end
      Result.new(triggered: false)
    rescue StandardError => e
      Rails.logger.warn("[Bella::SecretPhraseChecker] #{e.class}: #{e.message[0, 200]}")
      Result.new(triggered: false)
    end

    private

    def fire(sp)
      sp.update!(trigger_count: sp.trigger_count + 1, last_triggered_at: Time.current)

      if sp.action == 'pause_ai_and_notify'
        current_labels = @conversation.cached_label_list_array
        unless current_labels.include?('ai-off')
          begin
            @conversation.add_labels(['ai-off'])
          rescue StandardError => e
            Rails.logger.warn("[Bella::SecretPhraseChecker] add_labels failed: #{e.class}: #{e.message[0, 150]}")
          end
        end
      end

      safe_telegram do
        Games::TelegramNotifier.secret_phrase_triggered(
          account: @account,
          conversation: @conversation,
          phrase_record: sp
        )
      end
    end

    def safe_telegram
      yield
    rescue StandardError => e
      Rails.logger.warn("[Bella::SecretPhraseChecker] telegram failed: #{e.class}: #{e.message[0, 200]}")
    end
  end
end
