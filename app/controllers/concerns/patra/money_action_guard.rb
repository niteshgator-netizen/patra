# frozen_string_literal: true

# Dark-flag role guard for money-moving and money-config endpoints (HANDOFF-B-3).
#
#   PATRA_RESTRICT_MONEY_ACTIONS unset/false (DEFAULT): guard is a no-op —
#     byte-identical behavior to before the flag existed.
#   PATRA_RESTRICT_MONEY_ACTIONS=true: administrators OR a membership whose custom_role
#     grants 'money_action_manage' (a cashier) may hit the guarded actions; everyone else
#     is denied with the same Pundit::NotAuthorizedError as before.
#
# Flip the env var on Render AFTER confirming your own user is administrator.
module Patra
  module MoneyActionGuard
    extend ActiveSupport::Concern

    private

    def check_money_action_authorization
      return unless ENV['PATRA_RESTRICT_MONEY_ACTIONS'].to_s == 'true'

      return if money_action_permitted?

      raise Pundit::NotAuthorizedError
    end

    # Admins always; otherwise only a custom_role carrying 'money_action_manage' (cashier).
    # Fail-closed: any resolution error denies.
    def money_action_permitted?
      return true if Current.account_user&.administrator?

      permissions = Current.account_user&.custom_role&.permissions
      permissions.present? && permissions.include?('money_action_manage')
    rescue StandardError
      false
    end
  end
end
