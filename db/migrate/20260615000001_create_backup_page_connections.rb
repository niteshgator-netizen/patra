# frozen_string_literal: true

# Patra (B-CONN) — coverage ledger. Additive + reversible (drop_table). Tracks, per contact, which
# backup pages they have an OPEN messaging window with (i.e. have messaged). Unique (contact,page)
# makes writes idempotent.
class CreateBackupPageConnections < ActiveRecord::Migration[7.1]
  def change
    create_table :backup_page_connections do |t|
      t.bigint :account_id, null: false
      t.bigint :contact_id, null: false
      t.bigint :backup_page_id, null: false
      t.datetime :last_inbound_at

      t.timestamps
    end

    add_index :backup_page_connections, %i[contact_id backup_page_id], unique: true, name: 'idx_backup_conn_contact_page'
    add_index :backup_page_connections, :account_id
    add_index :backup_page_connections, :backup_page_id
  end
end
