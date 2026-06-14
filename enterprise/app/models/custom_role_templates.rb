# frozen_string_literal: true

# Patra (it7) — starting-point templates for the "Custom Roles" editor.
#
# A template is just a pre-fill of valid CustomRole::PERMISSIONS keys; after picking one the owner
# can tick/untick individual permissions. NOTE: a real "manager" is normally promoted to the
# administrator role instead (see the owner/manager model + main-feature grants); the manager
# template here is for owners who prefer an agent-level manager without full admin.
#
# Every permission listed below MUST be a member of CustomRole::PERMISSIONS. The PHASE Z
# templates-validity reviewer + the .valid? helper enforce this.
module CustomRoleTemplates
  TEMPLATES = [
    {
      key: 'manager',
      label: 'Manager',
      permissions: %w[
        conversation_manage
        conversation_unassigned_manage
        conversation_participating_manage
        contact_manage
        report_manage
        knowledge_base_manage
        view_all_inboxes
        contact_pii_full
      ]
    },
    {
      key: 'support',
      label: 'Support',
      permissions: %w[
        conversation_participating_manage
        contact_manage
        view_all_inboxes
      ]
    },
    {
      key: 'accountant',
      label: 'Accountant',
      permissions: %w[
        report_manage
        view_all_inboxes
      ]
    },
    {
      key: 'cashier',
      label: 'Cashier',
      permissions: %w[
        conversation_participating_manage
        contact_manage
        money_action_manage
      ]
    },
    {
      key: 'custom',
      label: 'Custom',
      permissions: []
    }
  ].freeze

  # True iff every template only references valid CustomRole permissions.
  def self.valid?
    TEMPLATES.all? { |template| (template[:permissions] - CustomRole::PERMISSIONS).empty? }
  rescue StandardError
    false
  end
end
