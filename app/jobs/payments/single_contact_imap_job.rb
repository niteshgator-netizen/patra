# frozen_string_literal: true

module Payments
  class SingleContactImapJob < ApplicationJob
    queue_as :low
    retry_on StandardError, wait: 10.seconds, attempts: 2

    def perform(contact_id, account_id)
      account = Account.find_by(id: account_id)
      contact = account&.contacts&.find_by(id: contact_id)
      return unless contact

      Payments::EmailConfirmationService.new(contact: contact).check_all
      Rails.logger.info("[SingleContactImapJob] checked contact=#{contact_id}")

      announce_verified_payment(account, contact)
    ensure
      ActiveRecord::Base.connection_pool.release_connection
    end

    private

    # After IMAP confirms, find a newly-verified payment that hasn't been announced/loaded yet.
    # Branch on score: auto-load, escalate to cashier, or no action.
    def announce_verified_payment(account, contact)
      contact.reload
      logs = Array(contact.custom_attributes['patra_finance_logs'])

      target = logs.reverse.find do |e|
        next false unless e.is_a?(Hash)
        next false unless e['status'].to_s.downcase.include?('verified')
        next false unless e['email_confirmed'] == true
        next false if e['load_announced'] == true
        next false if e['status'].to_s.downcase == 'loaded'
        next false if e['flag_reason'].to_s.strip.present?

        # Recency guard: only announce payments confirmed in the last 15 minutes
        confirmed_at = e['email_confirmed_at'].presence
        next false unless confirmed_at
        begin
          next false if Time.parse(confirmed_at) < 15.minutes.ago
        rescue StandardError
          next false
        end

        true # take the most recent verified+unannounced payment; branch on score below
      end

      return unless target

      platform_cfg = Payments::EmailConfirmationService.scoring_config_for(account, platform: target['platform'].to_s)
      score = Payments::EmailConfirmationService.confidence_score(target, account: account)['total'].to_i
      auto_load = platform_cfg['auto_load_threshold'].to_i
      escalate = platform_cfg['escalate_threshold'].to_i

      # Mark announced FIRST so it never double-fires even if the rest raises
      mark_announced!(contact, target)
      amount = target['amount']
      conv = account.conversations.where(contact_id: contact.id).order(last_activity_at: :desc).first
      return unless conv

      if score >= auto_load
        Rails.logger.info("[SingleContactImapJob] auto-load announce amount=#{amount} score=#{score} contact=#{contact.id}")
        Payments::AnnounceVerifiedPaymentJob.perform_later(account.id, contact.id, conv.display_id, amount)
      elsif score >= escalate
        Rails.logger.info("[SingleContactImapJob] escalate-to-cashier amount=#{amount} score=#{score} contact=#{contact.id}")
        # Tell the customer we're verifying
        begin
          Messaging::OutboundDispatcher.send(
            inbox: conv.inbox,
            conversation: conv,
            text: "got your $#{amount} payment — verifying it now, a teammate will confirm shortly 🙏"
          )
        rescue StandardError => e
          Rails.logger.error("[SingleContactImapJob] escalate customer msg failed: #{e.message}")
        end
        # Ping the cashier on Telegram
        begin
          Games::TelegramNotifier.human_escalation(
            account: account,
            contact: contact,
            reason: "Payment $#{amount} (#{target['platform']}) scored #{score}, below auto-load #{auto_load} — needs manual approval",
            conversation: conv
          )
        rescue StandardError => e
          Rails.logger.error("[SingleContactImapJob] escalate telegram failed: #{e.message}")
        end
      else
        Rails.logger.info("[SingleContactImapJob] below-escalate score=#{score} amount=#{amount} contact=#{contact.id} — no action")
      end
    rescue StandardError => e
      Rails.logger.error("[SingleContactImapJob] announce failed contact=#{contact&.id} #{e.class}: #{e.message}")
    end

    def mark_announced!(contact, target)
      logs = Array(contact.custom_attributes['patra_finance_logs'])
      logs.each do |e|
        if e.is_a?(Hash) && e['image_url'] == target['image_url'] && e['amount'] == target['amount']
          e['load_announced'] = true
        end
      end
      attrs = contact.custom_attributes.dup
      attrs['patra_finance_logs'] = logs
      contact.update_columns(custom_attributes: attrs)
    end
  end
end
