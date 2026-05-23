# frozen_string_literal: true

class ProcessZernioInboundJob < ApplicationJob
  queue_as :default

  retry_on StandardError, wait: :exponentially_longer, attempts: 5

  def perform(payload)
    account_section = payload['account'] || {}
    zernio_account_id = account_section['id'] || account_section['accountId']

    if zernio_account_id.blank?
      Rails.logger.warn("[ZernioJob] payload missing account.id payload_keys=#{payload.keys.inspect}")
      return
    end

    inbox = find_inbox_by_zernio_account(zernio_account_id)

    unless inbox
      Rails.logger.warn("[ZernioJob] no inbox for zernio accountId=#{zernio_account_id}")
      return
    end

    parsed = Messaging::BaseProvider.for(inbox).parse_inbound(payload)
    Messaging::InboundDispatcher.new(inbox: inbox, parsed: parsed).perform
  rescue StandardError => e
    Rails.logger.error("[ZernioJob] inbox lookup or dispatch failed: #{e.class}: #{e.message}")
    raise
  end

  private

  def find_inbox_by_zernio_account(zernio_account_id)
    Inbox.where(messaging_provider: 'zernio').find do |i|
      i.channel&.additional_attributes&.dig('zernio_account_id') == zernio_account_id
    end
  end
end
