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
        message_edit_delete
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

  # Patra (A3) — the six canonical role TIERS rendered as badges on the Team & Roles screen.
  # Additive to TEMPLATES (which stays the starting-point pre-fills for the custom-role editor):
  #   * owner  — implicit, permanent, all-powerful (the account creator; never a custom_role).
  #   * admin  — the native `administrator` role (full access).
  #   * manager/cashier — custom roles seeded from the TEMPLATES of the same key.
  #   * agent  — the native `agent` role (front-line; no edit/delete by default).
  #   * viewer — a read-only custom role (reports + assigned conversations, no mutations).
  # `kind` tells the UI whether a tier is implicit / native / a custom_role.
  TIERS = [
    { key: 'owner',   label: 'Owner',   order: 0, kind: 'implicit', removable: false, all_powerful: true,
      description: 'Account creator. Permanent and all-powerful; cannot be removed or downgraded.' },
    { key: 'admin',   label: 'Admin',   order: 1, kind: 'native',   native_role: 'administrator', all_powerful: true,
      description: 'Full administrative access via the native administrator role.' },
    { key: 'manager', label: 'Manager', order: 2, kind: 'custom',   template_key: 'manager',
      description: 'Senior operator: manages conversations, contacts and reports, and may edit/delete messages.' },
    { key: 'cashier', label: 'Cashier', order: 3, kind: 'custom',   template_key: 'cashier',
      description: 'Handles money actions (loads/cashouts) on assigned conversations.' },
    { key: 'agent',   label: 'Agent',   order: 4, kind: 'native',   native_role: 'agent',
      description: 'Front-line operator on assigned conversations. Cannot edit/delete messages by default.' },
    { key: 'viewer',  label: 'Viewer',  order: 5, kind: 'custom',   read_only: true, default_permissions: %w[report_view],
      description: 'Read-only access to reports and assigned conversations. No mutations.' }
  ].freeze

  EXPECTED_TIER_KEYS = %w[owner admin manager cashier agent viewer].freeze

  # True iff every template only references valid CustomRole permissions.
  def self.valid?
    TEMPLATES.all? { |template| (template[:permissions] - CustomRole::PERMISSIONS).empty? }
  rescue StandardError
    false
  end

  # Ordered tier keys, e.g. for rendering badges left-to-right.
  def self.tier_keys
    TIERS.map { |tier| tier[:key] }
  end

  def self.tier(key)
    TIERS.find { |tier| tier[:key] == key.to_s }
  end

  # True iff all six expected tiers are present (unique keys) and every tier default permission
  # is a valid CustomRole permission. Fail-closed on any error.
  def self.tiers_valid?
    keys = tier_keys
    return false unless keys.uniq.length == keys.length
    return false unless (EXPECTED_TIER_KEYS - keys).empty?

    TIERS.all? { |tier| (Array(tier[:default_permissions]) - CustomRole::PERMISSIONS).empty? }
  rescue StandardError
    false
  end
end
