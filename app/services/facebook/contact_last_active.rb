# Tracks Facebook Messenger customer "last active" in Redis for dashboard presence.
# Key format: contact_last_active:<contact_id> → Unix timestamp (float string), no TTL.
module Facebook
  class ContactLastActive
    KEY_PREFIX = 'contact_last_active:'.freeze
    ONLINE_WINDOW = 1.minute
    MINUTES_WINDOW = 60.minutes
    HOURS_WINDOW = 24.hours

    class << self
      def redis_key(contact_id)
        "#{KEY_PREFIX}#{contact_id}"
      end

      def record!(contact_id, at: Time.current)
        return if contact_id.blank?

        Redis::Alfred.set(redis_key(contact_id), at.to_f.to_s)
      end

      def read_timestamp(contact_id)
        raw = Redis::Alfred.get(redis_key(contact_id))
        return nil if raw.blank?

        Time.zone.at(raw.to_f)
      end

      # @return [Hash] { online: Boolean, last_active: String or nil }
      def presence_payload(contact_id)
        ts = read_timestamp(contact_id)
        return { online: false, last_active: nil } if ts.nil?

        age = Time.current - ts
        text = format_last_active(age)

        {
          online: age <= ONLINE_WINDOW,
          last_active: text
        }
      end

      private

      def format_last_active(age)
        if age <= ONLINE_WINDOW
          I18n.t('contacts.facebook_presence.active_now')
        elsif age < MINUTES_WINDOW
          minutes = [1, (age / 1.minute).floor].max
          I18n.t('contacts.facebook_presence.active_minutes_ago', count: minutes)
        elsif age < HOURS_WINDOW
          hours = [1, (age / 1.hour).floor].max
          I18n.t('contacts.facebook_presence.active_hours_ago', count: hours)
        end
      end
    end
  end
end
