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
# Pure read-only. Fails CLOSED: any error -> nil. Avoids ActiveSupport and
# AR query methods on purpose so it stays pure-Ruby testable with fake rows.
module Bella
  class PaymentInfoBuilder
    # Fixed display order for the all-platforms one-liner (matches
    # PaymentHandle::PLATFORMS; kept local so this file has no model dep).
    PLATFORM_ORDER = %w[cashapp chime paypal venmo zelle bitcoin ethereum usdt].freeze
    SEPARATOR = ' · '

    def self.for(account:, platform: nil)
      return nil if account.nil? || !account.respond_to?(:payment_handles)

      handles = account.payment_handles.to_a
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

    private_class_method :best_handle, :display_of, :safe_log_warn
  end
end
