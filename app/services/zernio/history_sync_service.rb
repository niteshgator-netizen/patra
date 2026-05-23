# frozen_string_literal: true

# Bulk-imports historical Zernio conversations and messages into Patra so a
# newly-connected channel doesn't show up with an empty inbox.
#
# Flow:
#   1. Paginated GET /inbox/conversations?accountId=X — pull every conversation
#   2. For each conversation, paginated GET /inbox/conversations/{id}/messages
#      (oldest first so we create in chronological order)
#   3. For each message, find-or-create Contact + ContactInbox + Conversation +
#      Message via the same builder Phase D inbound uses
#      (ContactInboxWithContactBuilder) for race safety.
#   4. source_id on imported messages matches the live-webhook format (raw
#      zernio message id) so a subsequent webhook for the same message becomes
#      a no-op via the existing duplicate_message? check.
#
# Idempotent — safe to re-run. Best-effort — failures inside one conversation
# never block the rest; failures inside one message log a warning and move on.
#
# Called by Zernio::SyncHistoryJob (background) and the
# Patra::ChannelsController#resync admin endpoint.
module Zernio
  class HistorySyncService
    ZERNIO_BASE = 'https://zernio.com/api/v1'
    HTTP_TIMEOUT = 30
    PAGE_SIZE = 100
    INTER_PAGE_PAUSE = 0.1
    INTER_CONV_PAUSE = 0.2

    def initialize(account_id:, inbox_id:)
      @account = Account.find(account_id)
      @inbox = Inbox.find(inbox_id)
      @channel = @inbox.channel
      @zernio_account_id = @channel&.additional_attributes&.dig('zernio_account_id')
      @synced_count = 0
      @skipped_count = 0
      @errors_count = 0
    end

    def sync!
      validate_inbox!

      Rails.logger.info(
        "[Zernio::HistorySync] start inbox=#{@inbox.id} zernio_account_id=#{@zernio_account_id}"
      )

      conversations = fetch_all_conversations
      Rails.logger.info("[Zernio::HistorySync] fetched #{conversations.length} conversations")

      conversations.each_with_index do |conv, idx|
        sync_conversation(conv)
        sleep(INTER_CONV_PAUSE) if idx < conversations.length - 1
      end

      result = { synced: @synced_count, skipped: @skipped_count, errors: @errors_count }
      Rails.logger.info("[Zernio::HistorySync] done inbox=#{@inbox.id} #{result.inspect}")
      result
    end

    private

    def validate_inbox!
      raise ArgumentError, "inbox #{@inbox.id} is not a Zernio inbox" unless @inbox.messaging_provider == 'zernio'
      raise ArgumentError, "inbox #{@inbox.id} has no zernio_account_id on channel" if @zernio_account_id.blank?
    end

    def fetch_all_conversations
      all = []
      cursor = nil

      loop do
        params = { accountId: @zernio_account_id, limit: PAGE_SIZE, sortOrder: 'desc' }
        params[:cursor] = cursor if cursor.present?

        resp = zernio_get('/inbox/conversations', params)
        all.concat(Array(resp['data']))

        pagination = resp['pagination'].to_h
        break unless pagination['hasMore'] && pagination['nextCursor'].to_s.present?

        cursor = pagination['nextCursor']
        sleep(INTER_PAGE_PAUSE)
      end

      all
    end

    def sync_conversation(conv)
      conv_id = conv['id'].to_s
      return if conv_id.blank?

      cursor = nil
      loop do
        params = { accountId: @zernio_account_id, limit: PAGE_SIZE, sortOrder: 'asc' }
        params[:cursor] = cursor if cursor.present?

        resp = zernio_get("/inbox/conversations/#{conv_id}/messages", params)
        Array(resp['messages']).each { |msg| import_message(conv, msg) }

        pagination = resp['pagination'].to_h
        break unless pagination['hasMore'] && pagination['nextCursor'].to_s.present?

        cursor = pagination['nextCursor']
        sleep(INTER_PAGE_PAUSE)
      end
    rescue StandardError => e
      @errors_count += 1
      Rails.logger.error("[Zernio::HistorySync] conversation failed conv=#{conv['id']} #{e.class}: #{e.message}")
    end

    def import_message(conv, msg)
      external_message_id = msg['id'].to_s
      if external_message_id.blank?
        @errors_count += 1
        Rails.logger.warn("[Zernio::HistorySync] message missing id, skipping conv=#{conv['id']}")
        return
      end

      # Use the same source_id format the live webhook uses (Phase D
      # InboundDispatcher#create_message). This makes the live webhook a
      # no-op via duplicate_message? when it arrives for the same message
      # later, AND lets this whole sync be re-runnable safely.
      if @inbox.messages.exists?(source_id: external_message_id)
        @skipped_count += 1
        return
      end

      contact_inbox = find_or_create_contact_inbox(conv)
      conversation = find_or_create_conversation(conv, contact_inbox)

      message = build_message(msg, conversation, contact_inbox.contact)
      persist_attachments!(message, msg)
      message.save!

      @synced_count += 1
    rescue StandardError => e
      @errors_count += 1
      Rails.logger.warn(
        "[Zernio::HistorySync] message failed conv=#{conv['id']} msg=#{external_message_id} " \
        "#{e.class}: #{e.message}"
      )
    end

    def find_or_create_contact_inbox(conv)
      sender_id = (conv['participantId'].presence || conv['id']).to_s

      ContactInboxWithContactBuilder.new(
        source_id: sender_id,
        inbox: @inbox,
        contact_attributes: {
          name: conv['participantName'].presence || "Zernio User #{sender_id}",
          identifier: sender_id,
          additional_attributes: {
            zernio_sender_id: sender_id,
            zernio_platform: conv['platform']
          }.compact
        }
      ).perform
    end

    def find_or_create_conversation(conv, contact_inbox)
      external_id = conv['id'].to_s

      existing = @inbox.conversations
                       .where(contact_inbox_id: contact_inbox.id, identifier: external_id)
                       .first
      return existing if existing

      Conversation.create!(
        account_id: @inbox.account_id,
        inbox_id: @inbox.id,
        contact_id: contact_inbox.contact_id,
        contact_inbox_id: contact_inbox.id,
        identifier: external_id,
        status: historical_conversation_status,
        additional_attributes: {
          external_conversation_id: external_id,
          messaging_provider: 'zernio',
          platform: conv['platform'],
          synced_from_history: true
        }.compact
      )
    end

    # Imported historical conversations default to :resolved so a newly-
    # connected channel doesn't flood the agent's open queue with hundreds
    # of old threads. When a live webhook arrives for one of these threads,
    # InboundDispatcher#find_or_create_conversation (Phase F.D strict-mirror)
    # creates a fresh :open conversation — same lifecycle direct-Meta has.
    def historical_conversation_status
      :resolved
    end

    def build_message(msg, conversation, contact)
      created_at = parse_zernio_timestamp(msg['createdAt'] || msg['sentAt']) || Time.current
      is_outgoing = msg['direction'].to_s == 'outgoing'

      message = conversation.messages.new(
        account_id: @inbox.account_id,
        inbox_id: @inbox.id,
        message_type: (is_outgoing ? :outgoing : :incoming),
        content: msg['text'].presence || msg['message'].presence || '[no text]',
        source_id: msg['id'].to_s,
        sender: (is_outgoing ? nil : contact),
        status: :sent,
        content_attributes: {
          zernio_platform: msg['platform'] || conversation.additional_attributes&.dig('platform'),
          zernio_timestamp: msg['sentAt'] || msg['createdAt'],
          zernio_message_id: msg['id'],
          synced_from_history: true
        }.compact
      )

      # Preserve the original Zernio timestamp so the conversation thread
      # orders correctly in the UI — without this, every imported message
      # would be stamped "now" and the thread would be incoherent.
      message.created_at = created_at
      message.updated_at = created_at
      message
    end

    def persist_attachments!(message, msg)
      Array(msg['attachments']).each do |att|
        next if att.blank?

        att_h = att.respond_to?(:with_indifferent_access) ? att.with_indifferent_access : att
        att_url = att_h['url'].presence || att_h.dig('payload', 'url').presence
        next if att_url.blank?

        message.attachments.build(
          account_id: @inbox.account_id,
          file_type: map_zernio_attachment_type(att_h['type'].to_s.downcase),
          external_url: att_url
        )
      end
    rescue StandardError => e
      # Bad attachment shape doesn't kill the message — same posture as
      # Phase G Item 1's InboundDispatcher#persist_message_attachments!.
      Rails.logger.warn(
        "[Zernio::HistorySync] attachment build failed msg_id=#{msg['id']} #{e.class}: #{e.message}"
      )
    end

    # Mirrors Messaging::InboundDispatcher#map_zernio_attachment_type (Phase G).
    def map_zernio_attachment_type(att_type)
      case att_type
      when 'image', 'photo'   then :image
      when 'video'            then :video
      when 'audio', 'voice'   then :audio
      when 'file', 'document' then :file
      else :file
      end
    end

    def parse_zernio_timestamp(raw)
      return nil if raw.blank?

      Time.zone.parse(raw.to_s)
    rescue ArgumentError, TypeError
      nil
    end

    # ---------- HTTP (HTTParty, matches Messaging::ZernioProvider + OauthService) ----------

    def api_key
      ENV.fetch('ZERNIO_API_KEY') { raise 'ZERNIO_API_KEY not set in Railway env' }
    end

    def auth_headers
      {
        'Authorization' => "Bearer #{api_key}",
        'Content-Type' => 'application/json',
        'Accept' => 'application/json'
      }
    end

    def zernio_get(path, query = {})
      response = HTTParty.get(
        "#{ZERNIO_BASE}#{path}",
        headers: auth_headers,
        query: query,
        timeout: HTTP_TIMEOUT
      )

      unless response.success?
        Rails.logger.error(
          "[Zernio::HistorySync] GET #{path} HTTP #{response.code} body=#{response.body.to_s[0, 200]}"
        )
        raise "Zernio GET #{path} failed: HTTP #{response.code}"
      end

      parsed = response.parsed_response
      parsed.is_a?(Hash) ? parsed : (JSON.parse(response.body.to_s) rescue {})
    end
  end
end
