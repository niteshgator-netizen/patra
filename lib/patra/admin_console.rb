# frozen_string_literal: true

module Patra
  # Kill-switch for operator-console MUTATING actions (account suspend/
  # reactivate, feature-flag toggle, impersonation, banner posting).
  # Read-only console pages are always available to authenticated super
  # admins; mutations additionally require PATRA_ADMIN_CONSOLE_ACTIONS=true
  # so the console ships default-OFF. The features.yml entry
  # `patra_operator_console` (enabled: false) is the per-account flag the
  # console can grant tenants later; this env var gates the console's own
  # write surface platform-wide.
  module AdminConsole
    ACTIONS_ENV_KEY = 'PATRA_ADMIN_CONSOLE_ACTIONS'

    module_function

    def actions_enabled?
      ENV.fetch(ACTIONS_ENV_KEY, 'false').to_s.casecmp('true').zero?
    end
  end
end
