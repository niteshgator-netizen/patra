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
# - 'contact_pii_hidden': Name-privacy => player name fully hidden ("Player").
#   When neither contact_pii_* is present the role sees first-name-only (the default).

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
    contact_pii_hidden
  ].freeze

  validates :name, presence: true
  validates :permissions, inclusion: { in: PERMISSIONS }
end
