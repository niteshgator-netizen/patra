# frozen_string_literal: true

module Backup
  # Runs when the active FB page is banned and a backup is promoted.
  #
  # FB policy posture: the old version posted a message into EVERY contact's
  # last conversation — untagged, no 24h-window check, no cap. At any real
  # contact volume that is a guaranteed run of policy (#10) violations landing
  # on the FRESH page. Now:
  #   1. ONE Telegram operator alert (always fires, even if notes fail)
  #   2. "we moved" note only for contacts with an INBOUND message in the last
  #      24h (inside the platform messaging window)
  #   3. hard cap (PATRA_MIGRATION_MAX_NOTES, default 50) + 1 note/second
  class CustomerMigration
    DEFAULT_MAX_NOTES = 50
    NOTE_WINDOW_HOURS = 24

    class << self
      def migrate(account, from:, to:)
        alert_operator(account, from, to)
        notes_sent = notify_recent_contacts(account)
        stamp_account!(account, from, to, notes_sent)
        notes_sent
      end

      private

      def max_notes
        raw = ENV.fetch('PATRA_MIGRATION_MAX_NOTES', '')
        # 0 is a valid operator choice (= telegram alert only, no auto-notes);
        # anything non-numeric falls back to the default.
        raw.match?(/\A\d+\z/) ? raw.to_i : DEFAULT_MAX_NOTES
      end

      def alert_operator(account, from, to)
        Games::TelegramNotifier.api_error(
          account: account,
          message: "Backup page switch: #{from.page_name} -> #{to.page_name}",
          details: "from=#{from.page_id} to=#{to.page_id} contacts=#{account.contacts.count} " \
                   "(auto-noting only contacts active in last #{NOTE_WINDOW_HOURS}h, cap #{max_notes})"
        )
      rescue StandardError => e
        Rails.logger.error("[Backup::CustomerMigration] operator alert failed: #{e.class}: #{e.message}")
      end

      def notify_recent_contacts(account)
        cap = max_notes
        return 0 if cap.zero?

        user = account.account_users.first&.user
        sent = 0

        recent_contacts(account).each do |contact|
          if sent >= cap
            Rails.logger.warn("[Backup::CustomerMigration] note cap #{cap} reached — remaining contacts skipped (operator was alerted)")
            break
          end

          begin
            conversation = contact.conversations.last
            next unless conversation
            next unless messaged_within_window?(conversation)

            sleep(1) if sent.positive? # rate limit: max 1 note/second
            message = "Hey! We've moved to a new page. This is still us — #{account.name}"
            Messages::MessageBuilder.new(user, conversation, { content: message, private: false }).perform
            sent += 1
          rescue StandardError => e
            Rails.logger.error("[Backup::CustomerMigration] note failed contact=#{contact.id}: #{e.class}: #{e.message}")
          end
        end

        sent
      end

      # Cheap pre-filter; the authoritative check is messaged_within_window?
      # (last INBOUND message — last_activity_at also moves on outbound).
      def recent_contacts(account)
        account.contacts.where('last_activity_at > ?', NOTE_WINDOW_HOURS.hours.ago)
      end

      def messaged_within_window?(conversation)
        last_inbound = conversation.messages
                                   .where(message_type: :incoming, private: false, sender_type: 'Contact')
                                   .maximum(:created_at)
        last_inbound.present? && last_inbound > NOTE_WINDOW_HOURS.hours.ago
      end

      def stamp_account!(account, from, to, notes_sent)
        attrs = account.custom_attributes || {}
        attrs['backup_migration'] = {
          from_page: from.page_id,
          to_page: to.page_id,
          at: Time.current.iso8601,
          notes_sent: notes_sent
        }
        account.update!(custom_attributes: attrs)
      rescue StandardError => e
        Rails.logger.error("[Backup::CustomerMigration] stamp failed: #{e.class}: #{e.message}")
      end
    end
  end
end
