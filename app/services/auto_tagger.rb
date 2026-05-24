# frozen_string_literal: true

class AutoTagger
  RULES = {
    'cashout' => ['cashout', 'redeem', 'withdraw', 'cash out'],
    'load' => ['load', 'deposit', 'add funds', 'send money'],
    'signup' => ['sign up', 'register', 'new account', 'create account'],
    'complaint' => ['complaint', 'problem', 'issue', 'not working', 'broken']
  }.freeze

  def self.tag(message)
    return unless message.message_type_incoming?

    text = message.content.to_s.downcase

    RULES.each do |label_name, keywords|
      next unless keywords.any? { |kw| text.include?(kw) }

      label = message.account.labels.find_or_create_by!(title: label_name)
      message.conversation.label_list.add(label.title)
      message.conversation.save!
    end
  rescue StandardError => e
    Rails.logger.error("[AutoTagger] failed: #{e.message}")
  end
end
