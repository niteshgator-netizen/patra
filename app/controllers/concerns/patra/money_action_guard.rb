# frozen_string_literal: true

# Dark-flag role guard for money-moving and money-config endpoints (HANDOFF-B-3).
#
#   PATRA_RESTRICT_MONEY_ACTIONS unset/false (DEFAULT): guard is a no-op —
#     byte-identical behavior to before the flag existed.
#   PATRA_RESTRICT_MONEY_ACTIONS=true: only administrators may hit the guarded
#     actions (delegates to the stock check_admin_authorization?).
#
# Flip the env var on Render AFTER confirming your own user is administrator.
module Patra
  module MoneyActionGuard
    extend ActiveSupport::Concern

    private

    def check_money_action_authorization
      return unless ENV['PATRA_RESTRICT_MONEY_ACTIONS'].to_s == 'true'

      check_admin_authorization?
    end
  end
end
