# frozen_string_literal: true

ActiveSupport::Reloader.to_prepare do
  Account.class_eval do
    has_many :audit_logs, dependent: :destroy_async
    has_many :approval_requests, dependent: :destroy_async
    has_many :scheduled_messages, dependent: :destroy_async
    has_many :player_bonuses, dependent: :destroy_async
    has_many :holidays, dependent: :destroy_async
  end
end
