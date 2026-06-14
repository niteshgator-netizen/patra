# frozen_string_literal: true

module Backup
  # Patra (B-DRIP) — the connect-up follow-up drip. SHIPS DARK.
  #
  # A send outside the FB 24-hour window BANS the page, so every layer here is a hard safety rail:
  #   * MASTER KILL SWITCH — ENV['PATRA_BACKUP_DRIP_ENABLED'] must be exactly 'true'. Unset/false =>
  #     #run is a pure no-op (returns 0, sends nothing), byte-identical to the drip not existing.
  #   * PER-ACCOUNT TOGGLE — account.custom_attributes['backup_drip_enabled'] must also be truthy.
  #   * WINDOW — a customer is messaged ONLY on a conversation with an inbound (from the contact) in
  #     the last 24h. This is the strict check (mirrors Backup::CustomerMigration), NOT
  #     MessageWindowService#can_reply? which can be true with a blank window.
  #   * RATE LIMIT — 1 send/second, hard cap MAX_SENDS_PER_RUN per account per run (never bursts).
  #   * IDEMPOTENT — a contact drip-messaged within the cadence (2/3/7 days) is skipped, so
  #     re-running the job within a cadence sends nothing new.
  class ConnectUpDrip
    FLAG = 'PATRA_BACKUP_DRIP_ENABLED'
    DEFAULT_CADENCE_DAYS = 3
    ALLOWED_CADENCES = [2, 3, 7].freeze
    MAX_SENDS_PER_RUN = 50
    WINDOW_HOURS = 24
    STAMP_KEY = 'backup_drip_last_sent_at'
    RECENT_CONVERSATIONS = 10

    def self.cadence_days(account)
      raw = account.custom_attributes&.dig('backup_drip_cadence_days').to_i
      ALLOWED_CADENCES.include?(raw) ? raw : DEFAULT_CADENCE_DAYS
    end

    def initialize(account)
      @account = account
    end

    # Returns the number of invites actually sent (always 0 when dark).
    def run
      return 0 unless enabled?

      live_backups = @account.backup_pages.live_backups.ordered.to_a
      return 0 if live_backups.empty?

      invite = Backup::InviteComposer.new(@account).message
      return 0 if invite.blank?

      sender = drip_sender_user
      return 0 if sender.nil?

      cadence = self.class.cadence_days(@account)
      sent = 0

      incomplete_contacts(live_backups).find_each do |contact|
        break if sent >= MAX_SENDS_PER_RUN
        next if drip_sent_recently?(contact, cadence)

        conversation = eligible_conversation(contact)
        next if conversation.nil?

        begin
          sleep(1) if sent.positive? # rate limit: never burst
          Messages::MessageBuilder.new(sender, conversation, { content: invite, private: false }).perform
          stamp_sent!(contact)
          sent += 1
        rescue StandardError => e
          Rails.logger.error("[Backup::ConnectUpDrip] send failed contact=#{contact.id}: #{e.class}: #{e.message}")
        end
      end

      stamp_run!
      sent
    end

    # Both gates must be on. Default (no flag / no toggle) => false => no send.
    def enabled?
      ENV[FLAG].to_s == 'true' && truthy?(@account.custom_attributes&.dig('backup_drip_enabled'))
    end

    private

    def truthy?(value)
      ActiveModel::Type::Boolean.new.cast(value) == true
    end

    # Customers connected to main but NOT to every live backup.
    def incomplete_contacts(live_backups)
      backup_ids = live_backups.map(&:id)
      return @account.contacts.none if backup_ids.empty?

      main = @account.backup_pages.main_pages.live.first
      customer_scope = BackupPageConnection.where(account_id: @account.id)
      customer_scope = customer_scope.where(backup_page_id: main.id) if main
      customer_ids = customer_scope.distinct.pluck(:contact_id)
      return @account.contacts.none if customer_ids.empty?

      full_counts = BackupPageConnection.where(account_id: @account.id, contact_id: customer_ids, backup_page_id: backup_ids)
                                        .group(:contact_id).count
      incomplete_ids = customer_ids.reject { |cid| full_counts[cid].to_i >= backup_ids.size }
      @account.contacts.where(id: incomplete_ids)
    end

    # The most recent conversation (on a real inbox) that still has an open 24h window. nil => skip.
    def eligible_conversation(contact)
      contact.conversations.where.not(inbox_id: nil)
             .order(last_activity_at: :desc).limit(RECENT_CONVERSATIONS)
             .detect { |conversation| window_open?(conversation) }
    end

    # STRICT: an inbound message from the contact within the last 24h. A blank/derived window is NOT
    # good enough — only a real recent inbound keeps a send inside FB policy.
    def window_open?(conversation)
      last_inbound = conversation.messages
                                 .where(message_type: :incoming, private: false, sender_type: 'Contact')
                                 .maximum(:created_at)
      last_inbound.present? && last_inbound > WINDOW_HOURS.hours.ago
    rescue StandardError
      false
    end

    def drip_sent_recently?(contact, cadence)
      raw = contact.additional_attributes&.dig(STAMP_KEY)
      return false if raw.blank?

      Time.zone.parse(raw.to_s) > cadence.days.ago
    rescue StandardError
      false
    end

    def stamp_sent!(contact)
      attrs = contact.additional_attributes || {}
      contact.update!(additional_attributes: attrs.merge(STAMP_KEY => Time.current.iso8601))
    rescue StandardError => e
      Rails.logger.error("[Backup::ConnectUpDrip] stamp failed contact=#{contact.id}: #{e.class}: #{e.message}")
    end

    def drip_sender_user
      @account.account_users.first&.user
    end

    def stamp_run!
      attrs = @account.custom_attributes || {}
      @account.update!(custom_attributes: attrs.merge('backup_drip_last_run_at' => Time.current.iso8601))
    rescue StandardError => e
      Rails.logger.error("[Backup::ConnectUpDrip] run stamp failed: #{e.class}: #{e.message}")
    end
  end
end
