# frozen_string_literal: true

# ADM5: append-only audit trail for super-admin (operator console) actions.
# Immutability is enforced at the application layer (PatraAdminAuditLog#readonly?
# + no update/destroy routes). DB-level REVOKE UPDATE/DELETE is documented
# future hardening in PATRA_FEAT_LOG.md.
class CreatePatraAdminAuditLogs < ActiveRecord::Migration[7.1]
  def change
    create_table :patra_admin_audit_logs do |t|
      t.bigint :admin_user_id, null: false
      t.string :action, null: false
      t.string :target_type
      t.bigint :target_id
      t.text :reason
      t.jsonb :metadata, default: {}, null: false
      t.string :ip_address
      t.datetime :created_at, null: false
    end

    add_index :patra_admin_audit_logs, :admin_user_id
    add_index :patra_admin_audit_logs, :action
    add_index :patra_admin_audit_logs, :created_at
    add_index :patra_admin_audit_logs, [:target_type, :target_id]
  end
end
