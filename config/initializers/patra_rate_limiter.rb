# frozen_string_literal: true

require_relative '../../app/middleware/patra_rate_limiter'

Rails.application.config.middleware.use PatraRateLimiter
