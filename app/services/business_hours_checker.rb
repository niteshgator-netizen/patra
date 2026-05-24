# frozen_string_literal: true

class BusinessHoursChecker
  def self.within_hours?(account)
    settings = account.settings || {}
    hours = settings['business_hours'] || settings[:business_hours]
    return true if hours.blank?

    tz = account.timezone.presence || 'UTC'
    now = Time.current.in_time_zone(tz)
    day_key = now.strftime('%A').downcase
    day_config = hours[day_key] || hours[day_key.to_sym]
    return false if day_config.blank? || day_config['closed'] || day_config[:closed]

    open_time = parse_time(day_config['open'] || day_config[:open], tz, now)
    close_time = parse_time(day_config['close'] || day_config[:close], tz, now)
    return true unless open_time && close_time

    now >= open_time && now <= close_time
  end

  def self.parse_time(time_str, tz, reference)
    return nil if time_str.blank?

    Time.use_zone(tz) { Time.zone.parse("#{reference.to_date} #{time_str}") }
  rescue ArgumentError
    nil
  end
end
