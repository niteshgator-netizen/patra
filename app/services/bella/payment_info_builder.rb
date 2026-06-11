# frozen_string_literal: true

# Deterministic payment-handle line(s) for Bella, built ONLY from the live
# payment_handles table — never a hardcoded handle.
#
# Bella::PaymentInfoBuilder.for(account:, platform: nil)
#   platform given -> "cashapp: $exacttag" (single best handle for it)
#   platform nil   -> one line, all platforms with a usable handle, stable
#                     order, " · " separator (one line: persona max-2-lines)
#   nothing usable -> nil (caller falls back to its existing escalation path)
#
# Health semantics (mirrors PaymentHandle#available? + HandleSelector.pick_active):
#   usable = status 'active' AND not in_cooldown?
#   best   = lowest [failure_count, priority]
#
# Fails CLOSED: any error -> nil. Avoids ActiveSupport and AR query methods
# on purpose so it stays pure-Ruby testable with fake rows. One deliberate
# write exists (MEGA2 P13): stale failure_counts decay lazily on this read
# path - see decay_stale_failures!.
module Bella
  class PaymentInfoBuilder
    # Fixed display order for the all-platforms one-liner (matches
    # PaymentHandle::PLATFORMS; kept local so this file has no model dep).
    PLATFORM_ORDER = %w[cashapp chime paypal venmo zelle bitcoin ethereum usdt].freeze
    SEPARATOR = ' · '

    def self.for(account:, platform: nil)
      return nil if account.nil? || !account.respond_to?(:payment_handles)

      handles = account.payment_handles.to_a
      decay_stale_failures!(account, handles)
      plat = platform.to_s.strip.downcase

      if !plat.empty?
        best = best_handle(handles, plat)
        return nil if best.nil?

        "#{plat}: #{display_of(best)}"
      else
        parts = PLATFORM_ORDER.filter_map do |p|
          best = best_handle(handles, p)
          "#{p} #{display_of(best)}" if best
        end
        return nil if parts.empty?

        parts.join(SEPARATOR)
      end
    rescue StandardError => e
      safe_log_warn("[PaymentInfoBuilder] failed: #{e.class}: #{e.message}")
      nil
    end

    # Single usable handle for a platform: active, not in cooldown, lowest
    # [failure_count, priority]. nil when nothing usable.
    def self.best_handle(handles, platform)
      candidates = Array(handles).select do |h|
        h.platform.to_s.downcase == platform &&
          h.status.to_s == 'active' &&
          !(h.respond_to?(:in_cooldown?) && h.in_cooldown?)
      end
      return nil if candidates.empty?

      candidates.min_by do |h|
        fc = h.respond_to?(:failure_count) ? h.failure_count.to_i : 0
        pr = h.respond_to?(:priority) ? (h.priority || 999).to_i : 999
        [fc, pr]
      end
    end

    # Exact display text from the row — character-for-character, zero
    # reformatting here (display_handle is the model's own canonical form,
    # the same one every other reply path sends).
    def self.display_of(handle)
      handle.respond_to?(:display_handle) ? handle.display_handle.to_s : handle.handle.to_s
    end

    def self.safe_log_warn(message)
      Rails.logger.warn(message) if defined?(Rails) && Rails.respond_to?(:logger) && Rails.logger
    rescue StandardError
      nil
    end

    # MEGA2 P13 - failure_count decay: a handle whose last_failure_at is older
    # than handle_decay_days (account custom_attributes, default 7; 0 disables)
    # gets failure_count reset to 0, lazily on this read path (no new cron) -
    # so a good handle stops rotting at the bottom forever (sofiamann8 case).
    # Handles with failures but NO last_failure_at are left alone (undatable).
    # Each decay is logged. Never raises.
    def self.decay_stale_failures!(account, handles)
      days = decay_days(account)
      return if days <= 0

      cutoff = Time.now.utc - (days * 86_400)
      Array(handles).each do |h|
        next unless h.respond_to?(:failure_count) && h.respond_to?(:last_failure_at) && h.respond_to?(:update)
        next unless h.failure_count.to_i.positive?
        next if h.last_failure_at.nil? || h.last_failure_at > cutoff

        old = h.failure_count.to_i
        h.update(failure_count: 0)
        safe_log_warn("[PaymentInfoBuilder] decayed failure_count #{old} -> 0 for handle ##{h.respond_to?(:id) ? h.id : '?'} (last failure #{h.last_failure_at}, decay #{days}d)")
      end
    rescue StandardError => e
      safe_log_warn("[PaymentInfoBuilder] decay failed: #{e.class}: #{e.message}")
    end

    def self.decay_days(account)
      attrs = account.respond_to?(:custom_attributes) ? (account.custom_attributes || {}) : {}
      v = attrs['handle_decay_days']
      return 7 if v.nil? || v.to_s.strip.empty?

      Integer(v.to_s.strip, exception: false) || 7
    rescue StandardError
      7
    end

    private_class_method :best_handle, :display_of, :safe_log_warn, :decay_stale_failures!, :decay_days
  end
end
