# frozen_string_literal: true

# Validates customer-supplied Meta app credentials by calling Meta Graph API.
# Returns { valid: true, app_name: ... } on success, raises Error on failure.
module Patra
  class MetaAppValidator
    class Error < StandardError; end

    GRAPH_URL = 'https://graph.facebook.com/v18.0'

    def initialize(app_id:, app_secret:)
      @app_id = app_id.to_s.strip
      @app_secret = app_secret.to_s.strip
    end

    def validate!
      raise Error, 'App ID required' if @app_id.blank?
      raise Error, 'App Secret required' if @app_secret.blank?

      response = HTTParty.get(
        "#{GRAPH_URL}/#{@app_id}",
        query: { access_token: "#{@app_id}|#{@app_secret}", fields: 'id,name,category' },
        timeout: 5
      )

      if response.success? && response.parsed_response['id'].to_s == @app_id
        {
          valid: true,
          app_id: @app_id,
          app_name: response.parsed_response['name'],
          app_category: response.parsed_response['category']
        }
      else
        err = response.parsed_response.dig('error', 'message') || 'Invalid credentials'
        raise Error, "Meta API rejected: #{err}"
      end
    rescue Net::ReadTimeout, Net::OpenTimeout
      raise Error, 'Meta API timeout. Try again.'
    end
  end
end
