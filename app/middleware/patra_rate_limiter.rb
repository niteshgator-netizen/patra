# frozen_string_literal: true

class PatraRateLimiter
  SKIP_PREFIXES = [
    '/app/',
    '/vite/',
    '/assets/',
    '/api/v1/',
    '/webhooks/',
    '/auth/'
  ].freeze

  SKIP_EXACT = ['/', '/favicon.ico', '/robots.txt'].freeze

  LIMITED_PREFIXES = {
    '/api/v2/widget/' => { count: 300, period: 60 },
    '/public/api/' => { count: 300, period: 60 }
  }.freeze

  def initialize(app)
    @app = app
  end

  def call(env)
    path = env['PATH_INFO'].to_s

    return @app.call(env) if skip_rate_limit?(path)

    limit_config = limit_for(path)
    return @app.call(env) unless limit_config

    request = Rack::Request.new(env)
    key = rate_limit_key(path, request.ip)

    return rate_limit_response(limit_config) if rate_limited?(key, limit_config)

    @app.call(env)
  end

  private

  def skip_rate_limit?(path)
    return true if SKIP_EXACT.include?(path)

    SKIP_PREFIXES.any? { |prefix| path.start_with?(prefix) }
  end

  def limit_for(path)
    LIMITED_PREFIXES.each do |prefix, config|
      return config if path.start_with?(prefix)
    end
    nil
  end

  def rate_limit_key(path, ip)
    if path.start_with?('/api/v2/widget/')
      "rl:widget:#{ip}"
    else
      "rl:public_api:#{ip}"
    end
  end

  def rate_limited?(key, config)
    count = Rails.cache.read(key).to_i
    if count >= config[:count]
      true
    else
      Rails.cache.write(key, count + 1, expires_in: config[:period].seconds)
      false
    end
  end

  def rate_limit_response(config)
    retry_after = config[:period]
    body = { error: 'Rate limit exceeded', retry_after: retry_after }.to_json
    [429, { 'Content-Type' => 'application/json', 'Retry-After' => retry_after.to_s }, [body]]
  end
end
