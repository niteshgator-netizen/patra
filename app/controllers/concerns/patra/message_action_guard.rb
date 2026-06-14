# frozen_string_literal: true

# Patra (B3) — role gate for editing/deleting customer-facing messages.
#
# Mirrors Patra::MoneyActionGuard / Patra::MainFeatureGuard in shape. It does NOT log or notify:
# message edit/delete accountability is ALREADY wired in config/initializers/patra_audit_hooks.rb
# (exactly one AuditLog row + one Telegram per edit/delete). This guard only ALLOWS or DENIES the
# action *before* it runs, so a denied attempt writes no audit row (nothing happened) and an allowed
# attempt still produces the single existing row — no double-logging.
#
#   * Owner + Admin (native administrators) always pass.
#   * A custom_role carrying 'message_edit_delete' passes (the Manager template includes it).
#   * Everyone else (Agent, Cashier, Viewer) is denied with "requires approval".
# Fail-closed: any resolution error denies.
module Patra
  module MessageActionGuard
    extend ActiveSupport::Concern

    private

    def authorize_message_edit_delete!
      return if message_edit_delete_permitted?

      render json: { error: 'requires approval' }, status: :forbidden
    end

    def message_edit_delete_permitted?
      return true if Current.account_user&.administrator?

      permissions = Current.account_user&.custom_role&.permissions
      permissions.present? && permissions.include?('message_edit_delete')
    rescue StandardError
      false
    end

    # A genuine content edit (not a status/pin update). Read from raw params so it is correct even
    # though MessagesController#permitted_params does not expose :content in this fork. The delete
    # path is gated unconditionally; only the shared `update` action needs this discriminator so
    # benign pin/status updates stay ungated.
    def message_content_edit_requested?
      params[:content].present? || params.dig(:message, :content).present?
    end
  end
end
