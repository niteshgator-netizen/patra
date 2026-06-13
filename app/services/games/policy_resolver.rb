# frozen_string_literal: true

module Games
  # it6 — Agent Policy resolver. PURE READ of account.settings['agent_policy'] (the agent-configurable
  # bonus/referral/cashout policy; see AccountSettingsSchema::AGENT_POLICY_SCHEMA). Given an account and
  # "now", it resolves which agent-defined bonuses are ACTIVE right now — schedule window evaluated in the
  # account's reporting_timezone — plus the referral and cashout policy.
  #
  # This is the SINGLE SOURCE OF TRUTH for any bonus %, referral rule, or cashout min/max/playthrough
  # that Bella is allowed to STATE to a customer (see Ai::ReplyService grounding hooks). It NEVER writes
  # and NEVER raises to callers — every public method rescues to a safe empty default. When the policy is
  # absent/empty, callers fall back to the legacy GameRule / generosity settings (backward-compat).
  #
  # Scheduling math is exposed as PURE class methods (window_matches?, hm_to_minutes, ...) so it can be
  # unit-tested without booting Rails.
  class PolicyResolver
    def self.for(account, now: Time.now)
      new(account: account, now: now)
    end

    def initialize(account:, now: Time.now)
      @account = account
      @now = now
    end

    # The raw policy hash (string-keyed), or {} if none/malformed.
    def policy
      @policy ||= begin
        raw = if @account.respond_to?(:agent_policy)
                @account.agent_policy
              else
                (@account.respond_to?(:settings) ? @account.settings : nil).to_h['agent_policy']
              end
        if raw.is_a?(Hash)
          raw.respond_to?(:deep_stringify_keys) ? raw.deep_stringify_keys : raw
        else
          {}
        end
      rescue StandardError
        {}
      end
    end

    # Has the owner configured ANY policy at all? (used to decide whether to show the policy prompt block)
    def configured?
      bonuses_configured? || referral_configured? || cashout_configured?
    rescue StandardError
      false
    end

    # --- bonuses -------------------------------------------------------------------------------------

    def bonuses
      arr = policy['bonuses']
      arr.is_a?(Array) ? arr.select { |b| b.is_a?(Hash) } : []
    rescue StandardError
      []
    end

    # True when the owner has defined at least one bonus (active or scheduled). When true, the agent_policy
    # is authoritative for bonus % and GameRule is NOT consulted (callers must defer if nothing is active).
    def bonuses_configured?
      bonuses.any?
    rescue StandardError
      false
    end

    # Bonuses that are enabled AND whose schedule window matches NOW in the account's reporting_timezone.
    def active_bonuses
      bonuses.select { |b| bonus_enabled?(b) && schedule_active?(b['schedule']) }
    rescue StandardError
      []
    end

    # Percent values Bella may state for a bonus right now (active bonuses only). [] => defer every promise.
    def active_bonus_percents
      active_bonuses.map { |b| numeric(b['percent']) }.compact
    rescue StandardError
      []
    end

    # --- referral ------------------------------------------------------------------------------------

    def referral
      r = policy['referral']
      r.is_a?(Hash) ? r : {}
    rescue StandardError
      {}
    end

    def referral_configured?
      truthy?(referral['active']) && !numeric(referral['percent']).nil?
    rescue StandardError
      false
    end

    # --- cashout -------------------------------------------------------------------------------------

    def cashout
      c = policy['cashout']
      c.is_a?(Hash) ? c : {}
    rescue StandardError
      {}
    end

    def cashout_configured?
      truthy?(cashout['active']) && (!numeric(cashout['min']).nil? || !numeric(cashout['max']).nil?)
    rescue StandardError
      false
    end

    # Cashout limits for a given platform (per_platform override) falling back to the global block.
    def cashout_for(platform = nil)
      base = cashout
      pp = base['per_platform']
      if platform && pp.is_a?(Hash) && pp[platform.to_s].is_a?(Hash)
        base.merge(pp[platform.to_s])
      else
        base
      end
    rescue StandardError
      {}
    end

    # --- scheduling (instance: needs account tz + now) -----------------------------------------------

    # Active when the schedule is "always" (or absent) or its window contains NOW in the account tz.
    def schedule_active?(sched)
      sched = {} unless sched.is_a?(Hash)
      mode = sched['mode'].to_s
      return true if mode.empty? || mode == 'always'
      return false unless mode == 'window'

      wday, minutes = now_wday_minutes
      self.class.window_matches?(days: sched['days'], start_hm: sched['start_hm'], end_hm: sched['end_hm'],
                                 wday: wday, minutes: minutes)
    rescue StandardError
      false
    end

    # --- scheduling (PURE — unit-testable without Rails) ---------------------------------------------

    # Does a window (days[], start_hm "HH:MM", end_hm "HH:MM") contain (wday 0=Sun, minutes-since-midnight)?
    # Same-day windows: start < end. Overnight windows (start >= end) span midnight, and the early-morning
    # portion is attributed to the PREVIOUS day's window (so "Fri 22:00–02:00" covers Sat 01:00). Empty/blank
    # days => every day. Returns false on any parse failure (fail-closed: never claims an unmatched bonus).
    def self.window_matches?(days:, start_hm:, end_hm:, wday:, minutes:)
      s = hm_to_minutes(start_hm)
      e = hm_to_minutes(end_hm)
      return false if s.nil? || e.nil?

      day_list = normalize_days(days)
      overnight = e <= s
      if overnight
        return true if minutes >= s && day_allowed?(day_list, wday)
        return true if minutes < e && day_allowed?(day_list, (wday - 1) % 7)

        false
      else
        return false unless minutes >= s && minutes < e

        day_allowed?(day_list, wday)
      end
    rescue StandardError
      false
    end

    # nil/empty day_list => allowed every day.
    def self.day_allowed?(day_list, wday)
      day_list.nil? || day_list.empty? || day_list.include?(wday)
    end

    # Array of ints 0..6, or nil when not an array (=> every day).
    def self.normalize_days(days)
      return nil unless days.is_a?(Array)

      days.map { |d| Integer(d.to_s, exception: false) }.compact.select { |d| d.between?(0, 6) }
    end

    # "HH:MM" -> minutes since midnight (0..1439), or nil when malformed.
    def self.hm_to_minutes(hm)
      m = hm.to_s.strip.match(/\A(\d{1,2}):(\d{2})\z/)
      return nil unless m

      h = m[1].to_i
      mi = m[2].to_i
      return nil unless h.between?(0, 23) && mi.between?(0, 59)

      (h * 60) + mi
    end

    private

    # active flag absent => enabled (a freshly-added bonus without the toggle still works); present => truthy.
    def bonus_enabled?(bonus)
      return false unless bonus.is_a?(Hash)

      bonus.key?('active') ? truthy?(bonus['active']) : true
    end

    # NOW in the account's reporting timezone => [wday(0=Sun), minutes-since-midnight].
    # Falls back to the raw clock when tz/ActiveSupport is unavailable.
    def now_wday_minutes
      tz = begin
        @account.respond_to?(:reporting_timezone) ? @account.reporting_timezone.to_s.strip : ''
      rescue StandardError
        ''
      end
      t = if !tz.empty? && @now.respond_to?(:in_time_zone) && defined?(ActiveSupport::TimeZone) && ActiveSupport::TimeZone[tz]
            @now.in_time_zone(tz)
          else
            @now
          end
      [t.wday, (t.hour * 60) + t.min]
    rescue StandardError
      [@now.wday, (@now.hour * 60) + @now.min]
    end

    def numeric(value)
      return nil if value.nil? || value == ''

      Float(value.to_s, exception: false)
    end

    def truthy?(value)
      [true, 'true', 1, '1'].include?(value)
    end
  end
end
