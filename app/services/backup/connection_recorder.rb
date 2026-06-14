# frozen_string_literal: true

module Backup
  # Patra (B-CONN) — records connections from inbound activity WITHOUT touching the realtime
  # (hot-file) inbound path. #record! is the idempotent primitive; #sweep is a scheduled
  # reconciliation that scans recent inbound on each live backup page's linked inbox and upserts
  # the connection rows. Pages with no inbox_id are skipped (we cannot observe their inbound).
  class ConnectionRecorder
    LOOKBACK_HOURS = 25 # a little over the 24h window so an hourly sweep never misses a connection

    def initialize(account)
      @account = account
    end

    def sweep
      recorded = 0
      @account.backup_pages.live.where.not(inbox_id: nil).find_each do |page|
        inbound_by_contact(page.inbox_id).each do |contact_id, last_at|
          next if contact_id.blank?

          contact = @account.contacts.find_by(id: contact_id)
          next if contact.nil?

          BackupPageConnection.record!(account: @account, contact: contact, backup_page: page, at: last_at)
          recorded += 1
        end
      end
      recorded
    end

    private

    # { contact_id => most_recent_inbound_at } for this inbox within the lookback window.
    def inbound_by_contact(inbox_id)
      Message.where(account_id: @account.id, inbox_id: inbox_id, message_type: :incoming, private: false, sender_type: 'Contact')
             .where('messages.created_at > ?', LOOKBACK_HOURS.hours.ago)
             .joins(:conversation)
             .group('conversations.contact_id')
             .maximum('messages.created_at')
    end
  end
end
