# frozen_string_literal: true

module Payments
  class ContactPaymentStatus
    RECENT_ACTIVITY_WINDOW = 24.hours
    VERIFYING_WINDOW = 30.minutes

    def initialize(contact:)
      @contact = contact
    end

    def status_code
      entry = latest_entry
      return :idle unless entry
      return :idle unless entry_recent?(entry, RECENT_ACTIVITY_WINDOW)

      return :flagged if entry['flag_reason'].to_s.strip.present?
      return :loaded if loaded_entry?(entry)
      return :verifying if verifying_entry?(entry)

      :idle
    end

    def display_pill
      case status_code
      when :loaded
        { label: 'Loaded', color: 'green', icon: '✅' }
      when :verifying
        { label: 'Verifying', color: 'blue', icon: '⏳' }
      when :flagged
        { label: 'Flagged', color: 'yellow', icon: '⚠️' }
      else
        { label: nil, color: 'gray', icon: nil }
      end
    end

    def latest_entry
      finance_logs.max_by { |entry| entry_timestamp(entry) || Time.at(0) }
    end

    private

    def finance_logs
      Array(@contact&.custom_attributes&.dig('patra_finance_logs')).filter_map do |raw|
        raw.is_a?(Hash) ? raw.stringify_keys : nil
      end
    end

    def entry_timestamp(entry)
      %w[recorded_at image_received_at logged_at ingested_at email_confirmed_at].each do |key|
        raw = entry[key]
        next if raw.blank?

        return raw if raw.is_a?(Time) || raw.is_a?(ActiveSupport::TimeWithZone)

        parsed = Time.zone.parse(raw.to_s)
        return parsed if parsed
      end
      nil
    rescue ArgumentError, TypeError
      nil
    end

    def entry_recent?(entry, window)
      ts = entry_timestamp(entry)
      ts.present? && ts >= window.ago
    end

    def loaded_entry?(entry)
      return true if entry['source'] == 'email_ghost_matched'

      entry['email_confirmed'] == true && successful_load_in_last_24h?
    end

    def verifying_entry?(entry)
      entry['email_confirmed'] != true &&
        entry['flag_reason'].to_s.strip.blank? &&
        entry_recent?(entry, VERIFYING_WINDOW)
    end

    def successful_load_in_last_24h?
      return false if @contact.blank?

      GameAction.where(contact_id: @contact.id, action_type: 'load', status: 'success')
                .where('created_at > ?', RECENT_ACTIVITY_WINDOW.ago)
                .exists?
    end
  end
end
