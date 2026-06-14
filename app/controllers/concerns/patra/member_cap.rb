# frozen_string_literal: true

# Patra (A3) — soft seat cap on the member invite path.
#
# Mirrors the existing agents usage-limit pattern (AgentsController#validate_limit) but is a
# SEPARATE Patra control: it does NOT read or touch billing `usage_limits`. The cap defaults to
# MEMBER_CAP_DEFAULT (50) and may be raised per-account via account.settings['member_cap'].
#
# Wiring: `include Patra::MemberCap` then `before_action :validate_member_cap, only: [:create]`
# (and :validate_member_cap_for_bulk for bulk invite). Remaining seats are surfaced read-only by
# Patra::SeatsController, which reuses the same helpers so there is a single source of truth.
module Patra
  module MemberCap
    extend ActiveSupport::Concern

    MEMBER_CAP_DEFAULT = 50

    private

    # The configured cap for this account (default 50). Any non-positive / unparseable override
    # falls back to the default — fail-safe toward the documented limit, never to "unlimited".
    def patra_member_cap
      raw = Current.account&.settings&.dig('member_cap')
      parsed = raw.to_i
      parsed.positive? ? parsed : MEMBER_CAP_DEFAULT
    rescue StandardError
      MEMBER_CAP_DEFAULT
    end

    # Current members = account memberships (includes invited-but-unconfirmed, which already hold a seat).
    def patra_member_count
      Current.account.account_users.count
    end

    def patra_seats_remaining
      [patra_member_cap - patra_member_count, 0].max
    end

    # before_action for single invite (create).
    def validate_member_cap
      return if patra_seats_remaining.positive?

      render_member_cap_reached
    end

    # before_action for bulk invite — must have room for EVERY requested email.
    def validate_member_cap_for_bulk
      requested = Array(params[:emails]).count
      return if requested <= patra_seats_remaining

      render_member_cap_reached
    end

    def render_member_cap_reached
      render json: {
        error: "Member cap reached (#{patra_member_cap}). Remove a member or raise the cap to invite more.",
        member_cap: patra_member_cap,
        members_used: patra_member_count,
        seats_remaining: patra_seats_remaining
      }, status: :forbidden
    end
  end
end
