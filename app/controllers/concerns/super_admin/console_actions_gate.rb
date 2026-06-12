# frozen_string_literal: true

# patra-fix2 G2: shared kill-switch response for every
# PATRA_ADMIN_CONSOLE_ACTIONS-gated mutation. The old per-controller copies
# rendered a raw text page; the operator now lands back on the page they came
# from with a styled flash banner (the super_admin layout renders flash via
# _flashes + the Patra restyle's .flash-alert).
module SuperAdmin::ConsoleActionsGate
  extend ActiveSupport::Concern

  CONSOLE_ACTIONS_DISABLED_MESSAGE =
    'Console actions are disabled. Set PATRA_ADMIN_CONSOLE_ACTIONS=true on Render to enable.'

  private

  def require_console_actions!
    return if Patra::AdminConsole.actions_enabled?

    redirect_back fallback_location: super_admin_root_path,
                  alert: CONSOLE_ACTIONS_DISABLED_MESSAGE
  end
end
