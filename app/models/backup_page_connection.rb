# frozen_string_literal: true

# Patra (B-CONN) — coverage ledger row: a contact has an open messaging window with a backup page.
# A row exists iff the contact has sent an inbound message to that page; last_inbound_at is the most
# recent inbound. Source of truth for Backup::CoverageStats and the connect-up drip's "incomplete"
# query. Writes go through .record! and are idempotent (unique contact+page).
class BackupPageConnection < ApplicationRecord
  belongs_to :account
  belongs_to :contact
  belongs_to :backup_page

  validates :contact_id, uniqueness: { scope: :backup_page_id }

  # Idempotent upsert: never creates a duplicate, only advances last_inbound_at forward. Safe to run
  # twice — re-recording the same (contact, page) updates the timestamp in place, adds no row.
  def self.record!(account:, contact:, backup_page:, at: Time.current)
    conn = find_or_initialize_by(contact_id: contact.id, backup_page_id: backup_page.id)
    conn.account_id ||= account.id
    conn.last_inbound_at = at if conn.last_inbound_at.nil? || at > conn.last_inbound_at
    conn.save!
    conn
  end
end
