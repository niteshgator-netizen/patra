if ENV['SENTRY_DSN'].present?
  Sentry.init do |config|
    config.dsn = ENV['SENTRY_DSN']
    config.enabled_environments = %w[staging production]

    # To activate performance monitoring, set one of these options.
    # We recommend adjusting the value in production:
    config.traces_sample_rate = 0.1 if ENV['ENABLE_SENTRY_TRANSACTIONS']

    config.excluded_exceptions += ['Rack::Timeout::RequestTimeoutException', 'MutexApplicationJob::LockAcquisitionError']

    # to track post data in sentry
    config.send_default_pii = true unless ENV['DISABLE_SENTRY_PII']

    # Patra: player message bodies, panel passwords and tokens must never land
    # in Sentry, even with send_default_pii on. Scrub by key, recursively.
    sensitive_keys = %w[
      content message text processed_message_content draft prefix
      password passwd login_pwd new_passwd
      access_token bot_token secret_key app_secret api_key authorization
    ].freeze
    scrubber = lambda do |obj, scrub|
      case obj
      when Hash
        obj.each do |k, v|
          if sensitive_keys.include?(k.to_s.downcase)
            obj[k] = '[SCRUBBED]'
          else
            scrub.call(v, scrub)
          end
        end
      when Array
        obj.each { |v| scrub.call(v, scrub) }
      end
      obj
    end
    config.before_send = lambda do |event, _hint|
      begin
        data = event.request&.data
        scrubber.call(data, scrubber) if data.is_a?(Hash) || data.is_a?(Array)
        scrubber.call(event.extra, scrubber) if event.respond_to?(:extra) && event.extra.is_a?(Hash)
      rescue StandardError
        # scrubbing must never block error delivery
      end
      event
    end
  end
end
