# frozen_string_literal: true

require 'time'

# Shared anti-spam guard for ALL automated outbound contact senders:
#   Contacts::ReEngageJob, Reengagement::DormantPlayerJob (via SendService),
#   Games::WinbackService.
# One stamp, one window: a contact touched by ANY automated sender is
# off-limits to EVERY automated sender for the window. Each job keeps its own
# longer job-specific cooldown on top of this.
# Stored in contact.custom_attributes (the codebase's contact-flag pattern,
# same as winback_last_contacted_at / last_reengagement_date).
module Reengagement
  module ContactCooldown
    KEY = 'last_automated_contact_at'
    # 72h: with four daily senders (08/09/12/17 UTC) a 24h window still allowed
    # the same player to be pinged on consecutive days by different jobs.
    DEFAULT_HOURS = 72

    module_function

    # Read at send-time so an ENV change applies without code changes.
    # Zero/negative/garbage values fall back to the default — this guard's
    # whole job is anti-spam, so it never silently disables itself.
    def window_hours
      hours = ENV.fetch('PATRA_REENGAGE_COOLDOWN_HOURS', DEFAULT_HOURS.to_s).to_i
      hours.positive? ? hours : DEFAULT_HOURS
    end

    def on_cooldown?(contact)
      ts = parse_time((contact.custom_attributes || {})[KEY])
      return false unless ts

      ts > Time.now.utc - (window_hours * 3600)
    end

    def stamp!(contact)
      attrs = (contact.custom_attributes || {}).merge(KEY => Time.now.utc.iso8601)
      contact.update(custom_attributes: attrs)
    rescue StandardError => e
      Rails.logger.error("[ContactCooldown] stamp failed contact=#{contact&.id}: #{e.message}")
    end

    def parse_time(raw)
      return nil if raw.nil? || raw.to_s.strip.empty?

      Time.parse(raw.to_s)
    rescue ArgumentError
      nil
    end
  end
end
