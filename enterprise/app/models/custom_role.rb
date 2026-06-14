# == Schema Information
#
# Table name: custom_roles
#
#  id          :bigint           not null, primary key
#  description :string
#  name        :string
#  permissions :text             default([]), is an Array
#  created_at  :datetime         not null
#  updated_at  :datetime         not null
#  account_id  :bigint           not null
#
# Indexes
#
#  index_custom_roles_on_account_id  (account_id)
#
#

# Available permissions for custom roles:
# - 'conversation_manage': Can manage all conversations.
# - 'conversation_unassigned_manage': Can manage unassigned conversations and assign to self.
# - 'conversation_participating_manage': Can manage conversations they are participating in (assigned to or a participant).
# - 'contact_manage': Can manage contacts.
# - 'report_manage': Can manage reports.
# - 'knowledge_base_manage': Can manage knowledge base portals.
# Patra (it7) additions:
# - 'view_all_inboxes': Can see every inbox regardless of assignment (support/manager emergency coverage).
# - 'money_action_manage': Can perform money actions when PATRA_RESTRICT_MONEY_ACTIONS=true.
# - 'contact_pii_full': Name-privacy => sees the FULL player name. Mutually exclusive with contact_pii_hidden.
# - 'contact_pii_first_name': Name-privacy => first name only ("John Dorian" -> "John"). Explicit form
#   of the default; lets the owner pick first-name in the role editor. Mutually exclusive with the other two.
# - 'contact_pii_hidden': Name-privacy => player name fully hidden ("Player").
#   When no contact_pii_* key is present the role still sees first-name-only (the default).
# Patra (it8) additions — the full Patra capability universe surfaced in the role editor.
# Enforcement status (honest: vocabulary present here != enforced everywhere yet):
# - 'message_edit_delete': ENFORCED — gates editing/deleting sent messages (it8 B3, messages controller).
# - 'view_all_inboxes' / 'money_action_manage' / 'contact_pii_*': ENFORCED (it7) via assigned_inboxes /
#   MoneyActionGuard / ContactPrivacy.
# - owner-only MAIN features are delegated via MainFeatureGuard grants, listed here only so the editor
#   can present them: facebook_connect_manage, payment_handle_manage, backup_page_manage,
#   game_credentials_manage, secrets_manage.
# - 'cashout_approve', 'report_view', 'team_manage', 'settings_manage', 'integrations_manage',
#   'channel_link_manage', 'incident_pause_ai', 'broadcast_send', 'bulk_reassign': capability VOCABULARY
#   — each enforced at its own controller/guard as that endpoint adopts the check. NO billing_manage:
#   billing is owner-only Account Settings, never a delegable team capability.

class CustomRole < ApplicationRecord
  belongs_to :account
  has_many :account_users, dependent: :nullify

  PERMISSIONS = %w[
    conversation_manage
    conversation_unassigned_manage
    conversation_participating_manage
    contact_manage
    report_manage
    knowledge_base_manage
    view_all_inboxes
    money_action_manage
    contact_pii_full
    contact_pii_first_name
    contact_pii_hidden
    cashout_approve
    message_edit_delete
    team_manage
    settings_manage
    integrations_manage
    facebook_connect_manage
    channel_link_manage
    backup_page_manage
    game_credentials_manage
    payment_handle_manage
    secrets_manage
    incident_pause_ai
    broadcast_send
    bulk_reassign
    report_view
  ].freeze

  validates :name, presence: true
  validates :permissions, inclusion: { in: PERMISSIONS }
end
