require 'net/http'
require 'uri'
require 'json'
require 'base64'

# Thin client for CapSolver's CAPTCHA-solving API.
# https://docs.capsolver.com/en/guide/recognition/ImageToTextTask/
#
# ImageToTextTask is SYNCHRONOUS — one POST returns the solution.
# No need for separate getTaskResult polling for this task type.
#
# Usage:
#   client = Games::CapsolverClient.new
#   text = client.solve_image_to_text(image_bytes, module_name: 'number')
#   # => "74461"
module Games
  class CapsolverClient
    API_URL = 'https://api.capsolver.com/createTask'.freeze
    OPEN_TIMEOUT = 10
    READ_TIMEOUT = 60   # CapSolver image solves usually <2s but allow headroom

    class CapsolverError < StandardError; end

    def initialize(api_key: nil)
      @api_key = api_key || ENV['CAPSOLVER_API_KEY'].to_s.strip
      raise CapsolverError, 'CAPSOLVER_API_KEY env var is not set' if @api_key.blank?
    end

    # Solves an image CAPTCHA. Returns the recognized text (e.g. "74461").
    #
    # Args:
    #   image_bytes  — raw image bytes (NOT base64; we encode here)
    #   module_name  — 'number' for digit-only, 'common' for general, etc.
    #
    # Raises CapsolverError on API failure, network failure, or empty solution.
    def solve_image_to_text(image_bytes, module_name: 'common')
      raise CapsolverError, 'image_bytes is blank' if image_bytes.to_s.bytesize.zero?

      body = {
        clientKey: @api_key,
        task: {
          type: 'ImageToTextTask',
          module: module_name,
          body: Base64.strict_encode64(image_bytes)
        }
      }.to_json

      response = post_json(API_URL, body)
      parsed = parse_json(response.body)

      if parsed['errorId'].to_i != 0
        raise CapsolverError, "CapSolver error: #{parsed['errorCode']} — #{parsed['errorDescription']}"
      end

      text = parsed.dig('solution', 'text').to_s.strip
      raise CapsolverError, "CapSolver returned blank solution: #{parsed.inspect}" if text.empty?

      text
    end

    private

    def post_json(url, body)
      uri = URI(url)
      Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == 'https',
                      open_timeout: OPEN_TIMEOUT, read_timeout: READ_TIMEOUT) do |http|
        req = Net::HTTP::Post.new(uri.request_uri)
        req['Content-Type'] = 'application/json'
        req.body = body
        response = http.request(req)
        unless response.is_a?(Net::HTTPSuccess)
          raise CapsolverError, "CapSolver HTTP #{response.code}: #{response.body.to_s[0..300]}"
        end
        response
      end
    rescue CapsolverError
      raise
    rescue Net::OpenTimeout, Net::ReadTimeout => e
      raise CapsolverError, "CapSolver timeout: #{e.message}"
    rescue StandardError => e
      raise CapsolverError, "CapSolver network error: #{e.class}: #{e.message}"
    end

    def parse_json(body)
      JSON.parse(body.to_s)
    rescue JSON::ParserError => e
      raise CapsolverError, "CapSolver returned invalid JSON: #{e.message} body=#{body.to_s[0..200]}"
    end
  end
end
