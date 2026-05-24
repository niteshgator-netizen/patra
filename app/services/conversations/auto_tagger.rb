# frozen_string_literal: true

module Conversations
  class AutoTagger
    DEFAULT_KEYWORDS = {
      'angry-customer' => %w[angry mad wtf scam],
      'refund-request' => %w[refund money\ back],
      'technical-issue' => %w[not\ working broken error],
      'positive-feedback' => %w[thank\ you thanks love]
    }.freeze

    def self.tag!(message)
      return unless message.incoming?

      account = message.account
      mapping = keyword_mapping(account)
      content = message.content.to_s.downcase
      labels = message.conversation.label_list

      mapping.each do |tag, keywords|
        next unless keywords.any? { |kw| content.include?(kw.downcase.gsub('\\', '')) }

        labels << tag unless labels.include?(tag)
      end

      message.conversation.update!(label_list: labels.uniq) if labels != message.conversation.label_list
    end

    def self.keyword_mapping(account)
      custom = (account.custom_attributes || {}).stringify_keys['keyword_tag_mapping']
      return DEFAULT_KEYWORDS if custom.blank?

      custom.transform_values { |v| Array(v) }
    end
  end
end
