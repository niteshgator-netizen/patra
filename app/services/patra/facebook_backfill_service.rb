# frozen_string_literal: true

module Patra
  class FacebookBackfillService
    class Error < StandardError; end

    RESOLVED_INACTIVITY = 7.days

    def initialize(inbox:, conversations_limit:, messages_per_conversation_limit:)
      @inbox = inbox
      @account = inbox.account
      @channel = inbox.channel
      @channel_attrs = (@channel.additional_attributes || {}).stringify_keys
      @page_id = @channel_attrs['fb_page_id'].to_s
      @page_access_token = @channel_attrs['fb_page_access_token'].to_s
      @conversations_limit = conversations_limit.to_i
      @messages_per_conversation_limit = messages_per_conversation_limit.to_i
      @profile_cache = {}
      @seen_contacts = Set.new
      @stats = { conversations_synced: 0, messages_synced: 0, contacts_synced: 0 }
      @processed_conversations = 0
    end

    def run!
      raise Error, 'Inbox channel is not Channel::Api' unless @inbox.channel_type == 'Channel::Api'
      raise Error, 'Missing fb_page_id on channel' if @page_id.blank?
      raise Error, 'Missing fb_page_access_token on channel' if @page_access_token.blank?

      fetch_and_process_conversations
      @stats
    end

    private

    def fetch_and_process_conversations
      conversations = Facebook::PatraGraphService.fetch_page_conversations(
        page_id: @page_id,
        page_access_token: @page_access_token,
        limit: @conversations_limit
      )

      conversations.each do |fb_conversation|
        process_conversation(fb_conversation)
        @processed_conversations += 1
        log_progress if (@processed_conversations % 10).zero?
      rescue StandardError => e
        Rails.logger.error(
          "[PatraBackfill] conversation failed inbox=#{@inbox.id} " \
          "fb_conversation=#{fb_conversation[:id]} #{e.class}: #{e.message}"
        )
      end
    end

    def process_conversation(fb_conversation)
      customer = customer_for(fb_conversation)
      customer_psid = customer[:id].to_s
      customer_name_from_convo = customer[:name].to_s
      return if customer_psid.blank?

      messages = Facebook::PatraGraphService.fetch_conversation_messages(
        conversation_id: fb_conversation[:id],
        page_access_token: @page_access_token,
        limit: @messages_per_conversation_limit
      )
      return if messages.blank?

      contact = upsert_contact(customer_psid, prefilled_name: customer_name_from_convo)
      conversation = upsert_conversation(fb_conversation, contact)

      messages.each do |fb_message|
        upsert_message(fb_message, conversation, contact)
        enrich_contact_from_message(contact, fb_message) if contact_name_is_placeholder?(contact)
      end

      refresh_conversation_activity!(conversation, messages)
    end

    def customer_for(fb_conversation)
      Array(fb_conversation[:participants]).find { |p| p[:id].to_s != @page_id } || {}
    end

    def upsert_contact(fb_user_id, prefilled_name: nil)
      fb_user_id = fb_user_id.to_s
      profile = cached_messenger_profile(fb_user_id)
      name = prefilled_name.presence || profile[:name].presence || "Player #{fb_user_id.last(4)}"
      additional_attributes = {
        'fb_user_id' => fb_user_id,
        'fb_profile_pic' => profile[:profile_pic].to_s,
        'fb_profile_link' => "https://www.facebook.com/#{fb_user_id}"
      }.compact

      contact_inbox = ContactInboxWithContactBuilder.new(
        source_id: fb_user_id,
        inbox: @inbox,
        contact_attributes: {
          name: name,
          identifier: fb_user_id,
          account_id: @account.id,
          additional_attributes: additional_attributes,
          avatar_url: profile[:profile_pic].presence
        }
      ).perform

      contact = contact_inbox.contact
      merged_attrs = (contact.additional_attributes || {}).stringify_keys.merge(additional_attributes)
      contact.update!(additional_attributes: merged_attrs) if contact.additional_attributes != merged_attrs

      apply_contact_name!(contact, name)

      if @seen_contacts.add?(contact.id)
        @stats[:contacts_synced] += 1
      end

      contact
    end

    def upsert_conversation(fb_conversation, contact)
      fb_conversation_id = fb_conversation[:id].to_s
      conversation = @inbox.conversations.find_by(identifier: fb_conversation_id, account_id: @account.id)

      unless conversation
        contact_inbox = contact.contact_inboxes.find_by!(inbox_id: @inbox.id)
        conversation = Conversation.create!(
          account_id: @account.id,
          inbox_id: @inbox.id,
          contact_id: contact.id,
          contact_inbox_id: contact_inbox.id,
          identifier: fb_conversation_id,
          additional_attributes: { 'fb_conversation_id' => fb_conversation_id }
        )
        @stats[:conversations_synced] += 1
      end

      conversation
    end

    def upsert_message(fb_message, conversation, contact)
      fb_message_id = fb_message[:id].to_s
      return if fb_message_id.blank?
      return if @inbox.messages.exists?(source_id: fb_message_id)

      from_id = fb_message[:from_id].to_s
      incoming = from_id.present? && from_id != @page_id
      message_type = incoming ? :incoming : :outgoing
      content = fb_message[:message].presence || '[no text]'
      created_at = parse_fb_time(fb_message[:created_time]) || Time.current

      message = conversation.messages.new(
        account_id: @account.id,
        inbox_id: @inbox.id,
        message_type: message_type,
        content: content,
        source_id: fb_message_id,
        status: :sent,
        sender: incoming ? contact : nil
      )
      message.created_at = created_at
      message.updated_at = created_at
      message.save!

      @stats[:messages_synced] += 1
    end

    def refresh_conversation_activity!(conversation, messages)
      last_at = messages.filter_map { |m| parse_fb_time(m[:created_time]) }.max || Time.current
      status = last_at >= RESOLVED_INACTIVITY.ago ? :open : :resolved

      conversation.update!(
        status: status,
        last_activity_at: last_at,
        contact_last_seen_at: last_at
      )
    end

    def cached_messenger_profile(fb_user_id)
      @profile_cache[fb_user_id] ||= begin
        Facebook::PatraGraphService.fetch_messenger_user_profile(
          user_id: fb_user_id,
          page_access_token: @page_access_token
        ) || { id: fb_user_id, name: nil, profile_pic: nil }
      end
    end

    def contact_name_is_placeholder?(name_or_contact)
      name = name_or_contact.is_a?(Contact) ? name_or_contact.name.to_s : name_or_contact.to_s
      name.start_with?('Player ') && name.length <= 12
    end

    def apply_contact_name!(contact, candidate_name)
      return if candidate_name.blank?
      return unless contact_name_is_placeholder?(contact) && !contact_name_is_placeholder?(candidate_name)

      contact.update!(name: candidate_name)
    end

    def enrich_contact_from_message(contact, fb_message)
      from_name = fb_message.dig(:from, :name).to_s.presence || fb_message[:from_name].to_s
      from_id = fb_message.dig(:from, :id).to_s.presence || fb_message[:from_id].to_s
      return if from_name.blank?
      return if from_id == @page_id
      return if from_name == @inbox.name
      return unless contact_name_is_placeholder?(contact)

      contact.update!(name: from_name)
    end

    def parse_fb_time(raw)
      return nil if raw.blank?

      Time.zone.parse(raw.to_s)
    rescue ArgumentError
      nil
    end

    def log_progress
      Rails.logger.info(
        "[PatraBackfill] progress inbox=#{@inbox.id} processed_conversations=#{@processed_conversations} " \
        "stats=#{@stats.inspect}"
      )
    end
  end
end
