# frozen_string_literal: true

class CreatePaymentHandles < ActiveRecord::Migration[7.1]
  def change
    create_table :payment_handles do |t|
      t.references :account, null: false, foreign_key: true
      t.string :platform, null: false
      t.string :handle, null: false
      t.string :display_name
      t.integer :priority, null: false, default: 1
      t.string :status, null: false, default: 'active'
      t.integer :failure_count, default: 0
      t.datetime :last_used_at
      t.datetime :last_failure_at
      t.datetime :cooldown_until
      t.text :notes
      t.string :verification_email
      t.string :verification_email_password
      t.string :verification_email_host
      t.integer :verification_email_port, default: 993
      t.boolean :verification_email_ssl, default: true
      t.timestamps
    end
    add_index :payment_handles, %i[account_id platform priority]
    add_index :payment_handles, %i[account_id platform status]
  end
end
