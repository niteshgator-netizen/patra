# frozen_string_literal: true

# Patra (B-PAGES) — coverage-model fields on backup_pages. Additive + reversible (remove_column).
#   role     : 'main' (the primary page) or 'backup'. Existing rows default to 'backup'; the owner
#              designates one as 'main'. Does NOT touch the existing status enum (warming/failover).
#   inbox_id : optional link to the Patra inbox for this page, so the coverage sweep can observe
#              inbound per page without touching the realtime (hot-file) path.
class AddCoverageFieldsToBackupPages < ActiveRecord::Migration[7.1]
  def change
    add_column :backup_pages, :role, :string, null: false, default: 'backup'
    add_column :backup_pages, :inbox_id, :bigint
    add_index :backup_pages, :inbox_id
  end
end
