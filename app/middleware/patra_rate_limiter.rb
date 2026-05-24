# frozen_string_literal: true

class PatraRateLimiter
  LIMITS = {
    api: { count: 100, period: 60 },
    widget: { count: 30, period: 60 }
  }.freeze

  def initialize(app)
    @app = app
  end

  def call(env)
    request = Rack::Request.new(env)
    key = rate_limit_key(request)
    limit_config = limit_for(request)

    if rate_limited?(key, limit_config)
      return [429, { 'Content-Type' => 'application/json', 'Retry-After' => limit_config[:period].to_s },
              [{ error: 'Rate limit exceeded' }.to_json]]
    end

    @app.call(env)
  end

  private

  def rate_limit_key(request)
    if request.path.start_with?('/widget')
      "rl:widget:#{request.ip}"
    elsif request.path.start_with?('/api')
      account_id = request.path[%r{/accounts/(\d+)}, 1] || 'global'
      "rl:api:#{account_id}"
    else
      "rl:other:#{request.ip}"
    end
  end

  def limit_for(request)
    request.path.start_with?('/widget') ? LIMITS[:widget] : LIMITS[:api]
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
end
