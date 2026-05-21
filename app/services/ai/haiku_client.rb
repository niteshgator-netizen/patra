# frozen_string_literal: true

require 'net/http'
require 'json'
require 'uri'

module Ai
  class HaikuClient
    ANTHROPIC_URL = 'https://api.anthropic.com/v1/messages'
    MODEL = 'claude-haiku-4-5-20251001'
    MAX_TOKENS = 80
    TIMEOUT_SEC = 8

    def initialize(system_prompt:, conversation_history:)
      @system_prompt = system_prompt.to_s
      @conversation_history = Array(conversation_history)
    end

    def generate_reply(rag_examples_block: '')
      api_key = ENV['ANTHROPIC_API_KEY'].to_s
      return nil if api_key.blank?

      system_prompt = @system_prompt
      system_prompt = "#{system_prompt}\n\n#{rag_examples_block}" unless rag_examples_block.to_s.strip.empty?

      anthropic_messages = @conversation_history.map do |m|
        role = m['role'].to_s == 'assistant' ? 'assistant' : 'user'
        { role: role, content: m['content'].to_s }
      end

      body = {
        model: MODEL,
        max_tokens: MAX_TOKENS,
        system: system_prompt,
        messages: anthropic_messages
      }

      started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      response = post_json(body, api_key)
      elapsed_ms = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - started) * 1000).round

      unless response.is_a?(Net::HTTPSuccess)
        Rails.logger.warn("[HaikuClient] HTTP #{response&.code} body=#{response&.body.to_s.truncate(500)}")
        return nil
      end

      parsed = parse_json_safe(response.body)
      return nil if parsed.nil?

      text = extract_text_content(parsed)
      return nil if text.blank?

      usage = parsed['usage'] || {}
      Rails.logger.info(
        "[HaikuClient] duration=#{elapsed_ms}ms tokens_in=#{usage['input_tokens']} tokens_out=#{usage['output_tokens']}"
      )

      text
    rescue StandardError => e
      Rails.logger.warn("[HaikuClient] error #{e.class}: #{e.message}")
      nil
    end

    private

    def post_json(payload_hash, api_key)
      uri = URI(ANTHROPIC_URL)
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = true
      http.open_timeout = TIMEOUT_SEC
      http.read_timeout = TIMEOUT_SEC

      req = Net::HTTP::Post.new(uri)
      req['x-api-key'] = api_key
      req['anthropic-version'] = '2023-06-01'
      req['content-type'] = 'application/json'
      req.body = payload_hash.to_json

      http.request(req)
    end

    def parse_json_safe(raw)
      JSON.parse(raw.to_s)
    rescue JSON::ParserError
      nil
    end

    def extract_text_content(parsed)
      blocks = parsed['content']
      return nil unless blocks.is_a?(Array)

      texts = blocks.filter_map do |block|
        next unless block.is_a?(Hash) && block['type'] == 'text'

        block['text'].to_s
      end
      texts.join.strip.presence
    end
  end
end
