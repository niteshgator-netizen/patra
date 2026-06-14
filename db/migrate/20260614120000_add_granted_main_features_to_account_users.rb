# frozen_string_literal: true

# Patra (it7) — per-membership grants for owner-only "main features".
#
# The workspace owner can grant a non-owner administrator (a "manager") specific main features
# (facebook_connections, payment_handles, backup_pages, roles, billing, game_credentials). This is
# an additive jsonb array column defaulting to [] — safe and reversible on a live DB.
class AddGrantedMainFeaturesToAccountUsers < ActiveRecord::Migration[7.1]
  def change
    add_column :account_users, :granted_main_features, :jsonb, default: [], null: false
  end
end
