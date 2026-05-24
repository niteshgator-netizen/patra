require 'ruby_llm'

module Llm::Config
  DEFAULT_MODEL = 'gpt-4.1-mini'.freeze

  class << self
    def initialized?
      @initialized ||= false
    end

    def initialize!
      return if @initialized

      configure_ruby_llm
      @initialized = true
    end

    def reset!
      @initialized = false
    end

    def with_api_key(api_key, api_base: nil)
      initialize!
      context = RubyLLM.context do |config|
        if xai_api_key.present?
          config.openai_api_key = xai_api_key
          config.openai_api_base = xai_api_base
        else
          config.openai_api_key = api_key
          config.openai_api_base = api_base
        end
      end

      yield context
    end

    def xai_configured?
      xai_api_key.present?
    end

    def xai_model
      ENV.fetch('XAI_MODEL', 'grok-4.3')
    end

    private

    def configure_ruby_llm
      RubyLLM.configure do |config|
        if xai_api_key.present?
          config.openai_api_key = xai_api_key
          config.openai_api_base = xai_api_base
        else
          config.openai_api_key = system_api_key if system_api_key.present?
          config.openai_api_base = openai_endpoint.chomp('/') if openai_endpoint.present?
        end
        config.model_registry_file = Rails.root.join('config/llm_models.json').to_s
        config.logger = Rails.logger
      end
    end

    def xai_api_key
      ENV['XAI_API_KEY'].to_s.presence
    end

    def xai_api_base
      'https://api.x.ai/v1'
    end

    def system_api_key
      InstallationConfig.find_by(name: 'CAPTAIN_OPEN_AI_API_KEY')&.value
    end

    def openai_endpoint
      InstallationConfig.find_by(name: 'CAPTAIN_OPEN_AI_ENDPOINT')&.value
    end
  end
end
