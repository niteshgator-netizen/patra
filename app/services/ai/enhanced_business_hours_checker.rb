# frozen_string_literal: true

module Ai
  class EnhancedBusinessHoursChecker
    PATRA_IPS = %w[184.169.168.179 18.144.142.102 172.59.194.86].freeze

    def self.open_now?(account, inbox: nil)
      return false if holiday_closed?(account, inbox)

      attrs = (account.custom_attributes || {}).stringify_keys
      hours = attrs['business_hours'] || {}
      return true if hours.blank?

      tz = ActiveSupport::TimeZone[hours['timezone'] || 'UTC']
      now = tz.now
      day_key = now.strftime('%A').downcase

      ranges = Array(hours['ranges']).presence
      if ranges
        return ranges.any? do |range|
          range['day'] == day_key && within_range?(now, range['start'], range['end'])
        end
      end

      days = Array(hours['days']).map(&:downcase)
      return false unless days.include?(day_key)

      within_range?(now, hours['start'], hours['end'])
    end

    def self.holiday_closed?(account, inbox)
      scope = Holiday.for_account(account.id).for_date(Date.current)
      scope = scope.where(inbox_id: [nil, inbox&.id]) if inbox
      scope.exists?
    end

    def self.within_range?(time, start_str, end_str)
      start_t = time.change(hour: start_str.to_s.split(':')[0].to_i, min: start_str.to_s.split(':')[1].to_i)
      end_t = time.change(hour: end_str.to_s.split(':')[0].to_i, min: end_str.to_s.split(':')[1].to_i)
      time >= start_t && time <= end_t
    end

    def self.provider_ips
      PATRA_IPS
    end
  end
end
