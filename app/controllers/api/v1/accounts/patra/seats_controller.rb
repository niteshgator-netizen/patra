# frozen_string_literal: true

# Patra (A3) — read-only seat usage for the Team & Roles screen ("x / 50 seats").
#
# Additive: a brand-new endpoint that changes no existing response. Reuses Patra::MemberCap so the
# numbers here are exactly what the invite-path before_action enforces (one source of truth).
class Api::V1::Accounts::Patra::SeatsController < Api::V1::Accounts::BaseController
  include Patra::MemberCap

  def show
    render json: {
      cap: patra_member_cap,
      used: patra_member_count,
      remaining: patra_seats_remaining
    }
  end
end
