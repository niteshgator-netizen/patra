# frozen_string_literal: true

module Ai
  class BusinessHoursChecker
    def self.within_hours?(account)
      hours = account.custom_attributes&.dig('business_hours')
      return true unless hours

      tz = ActiveSupport::TimeZone[hours['timezone']] || Time.zone
      now = Time.current.in_time_zone(tz)
      day = now.strftime('%A').downcase

      return false unless hours['days']&.include?(day)

      start_h, start_m = hours['start'].to_s.split(':').map(&:to_i)
      end_h, end_m = hours['end'].to_s.split(':').map(&:to_i)

      current_minutes = now.hour * 60 + now.min
      start_minutes = start_h * 60 + (start_m || 0)
      end_minutes = end_h * 60 + (end_m || 0)

      current_minutes.between?(start_minutes, end_minutes)
    end
  end
end
