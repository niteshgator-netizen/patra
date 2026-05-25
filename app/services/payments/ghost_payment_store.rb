# frozen_string_literal: true

module Payments
  class GhostPaymentStore
    STORAGE_KEY = 'payment_ghost_entries'
    LOCK_TIMEOUT = 5.seconds

    def initialize(account:)
      @account = account
    end

    def all
      Array(@account.custom_attributes&.dig(STORAGE_KEY)).map do |raw|
        raw.is_a?(Hash) ? raw.stringify_keys : raw
      end
    end

    def append!(ghost_hash)
      ghost = ghost_hash.stringify_keys
      mid = ghost['message_id'].to_s.strip
      return false if mid.present? && message_id_seen?(mid)

      with_store_lock do
        ghosts = all
        return false if mid.present? && ghosts.any? { |g| g['message_id'].to_s == mid }

        ghosts << ghost
        persist!(ghosts)
        true
      end
    end

    def find_unclaimed(within: 30.minutes)
      cutoff = within.ago
      all.select do |ghost|
        next false unless ghost['status'] == 'unclaimed'

        received_at = parse_time(ghost['email_received_at'])
        received_at.present? && received_at >= cutoff
      end
    end

    def message_id_seen?(message_id)
      mid = message_id.to_s.strip
      return false if mid.blank?

      return true if all.any? { |g| g['message_id'].to_s == mid }

      contact_message_id_seen?(mid)
    end

    def claim!(ghost_id:, contact:)
      with_store_lock do
        ghosts = all
        ghost = ghosts.find { |g| g['id'].to_s == ghost_id.to_s }
        raise ActiveRecord::RecordNotFound, "ghost #{ghost_id} not found" unless ghost

        ghost['status'] = 'claimed'
        ghost['claimed_by_contact_id'] = contact.id
        ghost['claimed_at'] = Time.current.iso8601
        persist!(ghosts)
        write_vault_entry!(contact, ghost)
        ghost
      end
    end

    def archive_expired!(older_than: 7.days)
      with_store_lock do
        ghosts = all
        changed = false
        cutoff = older_than.ago

        ghosts.each do |ghost|
          next unless ghost['status'] == 'unclaimed'

          ingested_at = parse_time(ghost['ingested_at'])
          next unless ingested_at && ingested_at < cutoff

          ghost['status'] = 'archived'
          changed = true
        end

        persist!(ghosts) if changed
      end
    end

    private

    def with_store_lock
      key = "ghost_store:#{@account.id}"
      lock_manager = Redis::LockManager.new
      if lock_manager.lock(key, LOCK_TIMEOUT)
        begin
          return yield
        ensure
          lock_manager.unlock(key)
        end
      end

      @account.with_lock { yield }
    rescue StandardError => e
      Rails.logger.warn("[GhostPaymentStore] Redis lock unavailable account=#{@account.id}: #{e.message}")
      @account.with_lock { yield }
    end

    def persist!(ghosts)
      attrs = (@account.custom_attributes || {}).stringify_keys
      attrs[STORAGE_KEY] = ghosts
      @account.custom_attributes = attrs
      @account.save!
    end

    def contact_message_id_seen?(message_id)
      @account.contacts.where("custom_attributes ? 'patra_finance_logs'").find_each do |contact|
        logs = Array(contact.custom_attributes['patra_finance_logs'])
        return true if logs.any? { |entry| entry.is_a?(Hash) && entry['message_id'].to_s == message_id }
      end
      false
    end

    def write_vault_entry!(contact, ghost)
      handle = PaymentHandle.find_by(id: ghost['payment_handle_id'])
      entry = {
        'kind' => 'deposit',
        'amount' => ghost['amount'],
        'platform' => ghost['platform'],
        'sender_name' => ghost['sender_name'],
        'sender_handle' => ghost['sender_handle'],
        'note_or_memo' => ghost['note'],
        'transaction_id' => ghost['transaction_id'],
        'recipient_handle' => handle&.display_handle,
        'status' => 'Verified',
        'raw_status' => 'completed',
        'email_confirmed' => true,
        'email_confirmed_at' => Time.current.iso8601,
        'email_match_source' => 'ghost_claim',
        'source' => 'email_ghost_matched',
        'ghost_id' => ghost['id'],
        'message_id' => ghost['message_id'],
        'recorded_at' => ghost['email_received_at'],
        'payment_handle_id' => ghost['payment_handle_id'],
        'image_received_at' => ghost['email_received_at']
      }

      attrs = (contact.custom_attributes || {}).stringify_keys
      logs = Array(attrs['patra_finance_logs'])
      logs << entry
      attrs['patra_finance_logs'] = logs
      contact.custom_attributes = attrs
      contact.save!(touch: false)
    end

    def parse_time(raw)
      return raw if raw.is_a?(Time) || raw.is_a?(ActiveSupport::TimeWithZone)

      Time.parse(raw.to_s)
    rescue ArgumentError, TypeError
      nil
    end
  end
end
