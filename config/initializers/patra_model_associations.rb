# frozen_string_literal: true

ActiveSupport::Reloader.to_prepare do
  Contact.class_eval do
    has_many :game_actions, dependent: :nullify
  end

  Account.class_eval do
    has_many :audit_logs, dependent: :destroy_async
    has_many :approval_requests, dependent: :destroy_async
    has_many :scheduled_messages, dependent: :destroy_async
    has_many :player_bonuses, dependent: :destroy_async
    has_many :holidays, dependent: :destroy_async
    has_many :automation_flows, dependent: :destroy_async
    has_many :drip_campaigns, dependent: :destroy_async
    has_many :broadcasts, dependent: :destroy_async
    has_many :usage_records, dependent: :destroy_async
    has_one :account_entitlement, dependent: :destroy
    has_many :agent_shifts, dependent: :destroy_async
    has_many :knowledge_articles, dependent: :destroy_async
    has_many :cashier_claims, dependent: :destroy_async
    has_many :backup_pages, dependent: :destroy_async
    has_many :accounting_syncs, dependent: :destroy_async
  end
end
