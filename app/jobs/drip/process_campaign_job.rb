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

      contacts.find_each do |contact|
        conversation = contact.conversations.where(account: campaign.account).last
        Automation::FlowExecutor.new(
          flow: campaign.automation_flow,
          conversation: conversation,
          contact: contact
        ).perform
        processed += 1
      end

      stats = campaign.stats.merge('processed' => processed)
      campaign.update!(stats: stats, status: 'completed')
    rescue StandardError => e
      Audit::Logger.log(action: 'job_failed', target: campaign, metadata: { job: self.class.name, error: e.message }) if defined?(Audit::Logger)
      raise
    end
  end
end
