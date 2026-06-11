# frozen_string_literal: true

module Drip
  class ProcessCampaignJob < ApplicationJob
    queue_as :low
    retry_on StandardError, wait: :polynomially_longer, attempts: 3

    def perform(campaign_id)
      campaign = DripCampaign.find(campaign_id)
      return unless campaign.status == 'active'

      contacts = Contacts::SegmentFilter.new(campaign.account, campaign.contact_segment).contacts
      processed = 0
      skipped_cooldown = 0

      contacts.find_each do |contact|
        # MEGA2 P9 - shared nudge guard: a contact touched by ANY automated
        # sender (re-engage/dormant/winback/drip) inside the window is skipped,
        # and a drip send stamps the SAME key those jobs check - max one nudge
        # per window across all of them.
        if Reengagement::ContactCooldown.on_cooldown?(contact)
          skipped_cooldown += 1
          next
        end

        conversation = contact.conversations.where(account: campaign.account).last
        executor = Automation::FlowExecutor.new(
          flow: campaign.automation_flow,
          conversation: conversation,
          contact: contact
        )
        executor.perform
        processed += 1
        if executor.sent_any_message?
          Reengagement::ContactCooldown.stamp!(contact)
          # MEGA2 P9 - stagger: spread the batch so 100 dormant players don't
          # all get pinged in the same second (FB ban risk).
          sleep(0.5 + rand * 2.0)
        end
      rescue StandardError => e
        # One bad contact must not abort the loop: retry_on would re-run the
        # WHOLE campaign and re-send to every already-processed contact.
        Rails.logger.error("[Drip::ProcessCampaignJob] campaign=#{campaign_id} contact=#{contact.id} #{e.class}: #{e.message}")
      end

      Rails.logger.info("[Drip::ProcessCampaignJob] campaign=#{campaign_id} processed=#{processed} skipped_cooldown=#{skipped_cooldown}")
      stats = campaign.stats.merge('processed' => processed, 'skipped_cooldown' => skipped_cooldown)
      campaign.update!(stats: stats, status: 'completed')
    rescue StandardError => e
      Audit::Logger.log(action: 'job_failed', target: campaign, metadata: { job: self.class.name, error: e.message }) if defined?(Audit::Logger)
      raise
    end
  end
end
